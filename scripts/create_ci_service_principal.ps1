#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Creates a Service Principal for GitHub workflow
.DESCRIPTION 
    This script creates a Service Principal with federated credentialss, so no Service Principal secrets have to maintained. If GitHub CLI is in the path, it will create the secrets required on the repository.
#>
#Requires -Version 7.2
param ( 
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")][string]$TenantId=$env:ARM_TENANT_ID,
    [parameter(Mandatory=$false,HelpMessage="Azure subscription ID")][string]$SubscriptionId=$env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false,HelpMessage="Azure resource group name")][string]$ResourceGroupName,
    [parameter(Mandatory=$false,HelpMessage="GitHub repository in <owner>/<name> format")][string]$RepositoryName,
    [parameter(Mandatory=$false,HelpMessage="Whether to set ARM_CLIENT_SECRET as repository secret")][switch]$CreateServicePrincipalPassword
) 

Write-Debug $MyInvocation.line

. (Join-Path $PSScriptRoot functions.ps1)

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Output "$($PSStyle.Formatting.Error)Git not found, exiting$($PSStyle.Reset)" | Write-Warning
    exit
}

Push-location $PSScriptRoot

switch -regex ($RepositoryName) {
    "^https://(?<host>[\w\.]+)/(?<repo>\w+/[\w\-]+)(\.git)?$" {
        $gitHost = $matches["host"]
        $RepositoryName = $matches["repo"]
        break
    }
    "^\w+/[\w\-]+$" {
        break
    }
    "^.*$" {
        Write-Output "$($PSStyle.Formatting.Error)'$RepositoryName' is not a valid repository name (<owner>/<name>), exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
    "" {
        # No parameter passed
        # Try to infer repository name from repo we're in
        $remoteRepoUrl = $(git config --get remote.origin.url)
        if ($remoteRepoUrl -match "^https://(?<host>[\w\.]+)/(?<repo>\w+/[\w\-]+)(\.git)?$") {
            $gitHost = $matches["host"]
            $inRepository = $true
            $RepositoryName = $matches["repo"]
        } else {
            Write-Warning "Could not determine repo name, exiting"
            exit
        }
        break
    }
    default {
        Write-Output "$($PSStyle.Formatting.Error)'$RepositoryName' is not a valid repository name, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
}
$gitHost ??= "github.com" # Assume as default
Write-Verbose "Using repository '$RepositoryName'"

# Prepare federation subjects
Write-Host "Preparing federation subjects..."
$subjects = [System.Collections.ArrayList]@("repo:${RepositoryName}:ref:refs/heads/main",`
            "repo:${RepositoryName}:ref:refs/heads/master",`
            "repo:${RepositoryName}:pull_request",`
            "repo:${RepositoryName}:ref:refs/tags/azure"`
)
if ($inRepository) {
    $currentBranch = $(git rev-parse --abbrev-ref HEAD)
    if ($currentBranch -notmatch "main|master") {
        $subjects.Add("repo:${RepositoryName}:ref:refs/heads/${currentBranch}") | Out-Null
    }
}

# Login to Azure CLI
Write-Host "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)
if (!$SubscriptionId) {
    $SubscriptionId = $(az account show --query id -o tsv)
}

# Create Service Principal
$servicePrincipalName = "$($RepositoryName -replace '/','-')-cicd"
Write-Host "Creating Service Principal with name '$servicePrincipalName'..."
$scope = "/subscriptions/${SubscriptionId}"
if ($ResourceGroupName) {
    $scope += "/resourceGroups/${ResourceGroupName}"
}
az ad sp create-for-rbac --name $servicePrincipalName `
                         --role Owner `
                         --scopes $scope | ConvertFrom-Json | Set-Variable servicePrincipal
$servicePrincipal | Format-List | Out-String | Write-Debug
$appId = $servicePrincipal.appId 
$appObjectId = $(az ad app show --id $appId --query objectId -o tsv)
$spPassword = $servicePrincipal.password
Write-Debug "appId: $appId"
Write-Debug "appObjectId: $appObjectId"

# Retrieve existing federation subjects
Write-Host "Retrieving existing federation subjects for Service Principal with client ID '$appId'..."
$getUrl = "https://graph.microsoft.com/beta/applications/${appObjectId}/federatedIdentityCredentials"
Write-Debug "getUrl: $getUrl"
Write-Verbose "Retrieving federations for application with object ID '${appObjectId}'..."
az rest --method GET `
        --headers '{\""Content-Type\"": \""application/json\""}' `
        --uri "$getUrl" `
        --body "@${requestBodyFile}" `
        --query "value[].subject" | ConvertFrom-Json | Set-Variable federatedSubjects

# Create federation subjects
Write-Host "Creating federation subjects for Service Principal with client ID '$appId'..."
foreach ($subject in $subjects) {
    if ($federatedSubjects -and $federatedSubjects.Contains($subject)) {
        Write-Verbose "Federation subject '$subject' already exists"
        continue
    }
    Write-Verbose "Creating federation subject '$subject'..."
    $federationName = ($subject -replace ":|/|_","-")

    Get-Content (Join-Path $PSScriptRoot "federated-identity-request-template.jsonc") | ConvertFrom-Json | Set-Variable request
    $request.name = $federationName
    $request.subject = $subject
    $request | Format-List | Out-String | Write-Debug

    # Pass JSON as file per best practice documented at:
    # https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md#double-quotes--are-lost
    $requestBodyFile = (New-TemporaryFile).FullName
    $request | ConvertTo-Json | Out-File $requestBodyFile
    Write-Debug "requestBodyFile: $requestBodyFile"

    $postUrl = "https://graph.microsoft.com/beta/applications/${appObjectId}/federatedIdentityCredentials"
    Write-Debug "postUrl: $postUrl"
    Write-Host "Adding federation for ${subject}..."
    az rest --method POST `
            --headers '{\""Content-Type\"": \""application/json\""}' `
            --uri "$postUrl" `
            --body "@${requestBodyFile}" | Set-Variable result
    if ($lastexitcode -ne 0) {
        Write-Error "Request to add subject '$subject' failed, exiting"
        exit
    }
}
Write-Host "Created federation subjects for GitHub repo '${RepositoryName}'"

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "Setting GitHub $RepositoryName secrets ARM_CLIENT_ID, ARM_TENANT_ID & ARM_SUBSCRIPTION_ID..."
    gh auth login -h $gitHost
    Write-Debug "Setting GitHub workflow secret ARM_CLIENT_ID='$appId'..."
    gh secret set ARM_CLIENT_ID -b $appId --repo $RepositoryName
    if ($CreateServicePrincipalPassword) {
        Write-Debug "Setting GitHub workflow secret ARM_CLIENT_SECRET='$spPassword'..."
        gh secret set ARM_CLIENT_SECRET -b $spPassword --repo $RepositoryName
    }
    Write-Debug "Setting GitHub workflow secret ARM_TENANT_ID='$TenantId'..."
    gh secret set ARM_TENANT_ID -b $TenantId --repo $RepositoryName
    Write-Debug "Setting GitHub workflow secret ARM_SUBSCRIPTION_ID='$SubscriptionId'..."
    gh secret set ARM_SUBSCRIPTION_ID -b $SubscriptionId --repo $RepositoryName
} else {
    # Show workflow configuration information
    Write-Warning "GitHub CLI not found, configure secrets manually"
    Write-Host "Set GitHub workflow secret ARM_CLIENT_ID='$appId' in $RepositoryName"
    if ($CreateServicePrincipalPassword) {
        Write-Host "Set GitHub workflow secret ARM_CLIENT_SECRET='$spPassword' in $RepositoryName"
    }
    Write-Host "Set GitHub workflow secret ARM_TENANT_ID='$TenantId' in $RepositoryName"
    Write-Host "Set GitHub workflow secret ARM_SUBSCRIPTION_ID='$SubscriptionId' in $RepositoryName"
}