#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Creates a Service Principal for GitHub Actions
.DESCRIPTION 
    This script creates a Service Principal with federated credentials, so no Service Principal secrets have to maintained. If GitHub CLI is in the path, it will create the secrets required on the repository.
.PARAMETER CreateServicePrincipalPassword
    While this script is intended to set up federation using workload identity, it can also create a Service Principal password. Use this switch to do so.
.PARAMETER SkipServicePrincipalFederation
    While this script is intended to set up federation using workload identity, it can also create a regular Service Principal. Use this switch to do so.
.PARAMETER ConfigureAzureCredentialsJson
    This switch will configure the AZURE_CREDENTIALS JSON formatted secret. You need to also speficy -CreateServicePrincipalPassword to have the Service Principal password included.
.LINK
    https://github.com/marketplace/actions/azure-login
#>
#Requires -Version 7.2
param ( 
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")][guid]$TenantId=$env:AZURE_TENANT_ID ?? $env:ARM_TENANT_ID,
    [parameter(Mandatory=$false,HelpMessage="Azure subscription id")][guid]$SubscriptionId=$env:AZURE_SUBSCRIPTION_ID ?? $env:ARM_SUBSCRIPTION_ID,
    [parameter(Mandatory=$false,HelpMessage="Azure resource group name")][string]$ResourceGroupName=$env:AZURE_RESOURCE_GROUP,
    [parameter(Mandatory=$false,HelpMessage="Azure RBAC role to assign to the Service Principal")][string]$AzureRole="Contributor",
    [parameter(Mandatory=$false,HelpMessage="GitHub repository in <owner>/<name> format")][string]$RepositoryName,
    [parameter(Mandatory=$false,HelpMessage="Branches to add federation subjects for")][string[]]$BranchNames=@("main","master"),
    [parameter(Mandatory=$false,HelpMessage="Tags to add federation subjects for")][string[]]$TagNames=@("azure"),
    [parameter(Mandatory=$false,HelpMessage="Whether to set AZURE_CLIENT_SECRET as repository secret")][switch]$CreateServicePrincipalPassword,
    [parameter(Mandatory=$false,HelpMessage="Whether to skip federation configuration")][switch]$SkipServicePrincipalFederation,
    [parameter(Mandatory=$false,HelpMessage="Whether to set AZURE_CREDENTIALS as repository secret")][switch]$ConfigureAzureCredentialsJson
) 

Write-Debug $MyInvocation.line

. (Join-Path $PSScriptRoot functions.ps1)

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Output "$($PSStyle.Formatting.Error)Git not found, exiting$($PSStyle.Reset)" | Write-Warning
    exit
}

switch -regex ($RepositoryName) {
    "^https://(?<host>[\w\.]+)/(?<repo>\w+/[\w\-]+)(\.git)?$" {
        $gitHost = $matches["host"]
        $RepositoryName = $matches["repo"]
        break
    }
    "^\w+/[\w\-]+$" {
        # Looks good
        break
    }
    "^.+$" {
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
$repositoryUrl = "https://${gitHost}/${RepositoryName}"
Write-Debug "repositoryUrl: $repositoryUrl"

# Login to Azure CLI
Write-Host "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)
if (!$SubscriptionId) {
    $SubscriptionId = $(az account show --query id -o tsv)
}

# Create Service Principal
$servicePrincipalName = "$($RepositoryName -replace '/','-')-cicd"
Write-Host "`nCreating Service Principal with name '$servicePrincipalName'..."
$scope = "/subscriptions/${SubscriptionId}"
if ($ResourceGroupName) {
    $scope += "/resourceGroups/${ResourceGroupName}"
}
$AzureRole ??= "Contributor"
$preSPCreationSnapshot = (get-date).ToUniversalTime().ToString("o") # Save timestamp before SP creation, so we can clean up secrets created
az ad sp create-for-rbac --name $servicePrincipalName `
                         --role $AzureRole `
                         --scopes $scope | ConvertFrom-Json | Set-Variable servicePrincipal
az ad sp list --display-name $servicePrincipalName --query "[0]" | ConvertFrom-Json | Set-Variable servicePrincipalData

# Capture Service Principal information
$servicePrincipal | Select-Object -ExcludeProperty password | Format-List | Out-String | Write-Debug
$servicePrincipalData | Format-List | Out-String | Write-Debug
$appId = $servicePrincipal.appId 
$appObjectId = $(az ad app show --id $appId --query id -o tsv)
Write-Debug "appId: $appId"
Write-Debug "appObjectId: $appObjectId"

if ($CreateServicePrincipalPassword) {
    $spPassword = $servicePrincipal.password
    $spPasswordMasked = $spPassword -replace ".","*"

    Write-Host "Service Principal password created is ${spPassword}"
} else {
    # Clean up secrets we did not ask for 
    Write-Debug "az ad app credential list --id ${appId}..."
    $keyToDelete = $(az ad app credential list --id $appId --query "[?startDateTime >= '$preSPCreationSnapshot'].keyId" -o tsv)
    if ($keyToDelete) {
        Write-Debug "Deleting credential key '$keyToDelete'..."
        az ad app credential delete --id $appId --key-id $keyToDelete | Write-Debug
    }   
}

# Update App object with repository information
Write-Host "`nUpdating application '$appId'..."
az ad app update --id $appId --web-home-page-url $repositoryUrl

# Create Azure SDK formatted JSON which the GitHub azure/login@v1 action can consume
$sdkCredentials = @{
    clientId = $servicePrincipal.appId
    objectId = $servicePrincipalData.id
    subscriptionId = $SubscriptionId
    tenantId = $servicePrincipal.tenant
}
$sdkCredentialsMasked = $sdkCredentials.Clone()
if ($CreateServicePrincipalPassword) {
    $sdkCredentials["clientSecret"] = $spPassword
    $sdkCredentialsMasked["clientSecret"] = $spPasswordMasked
}
$sdkCredentials | ConvertTo-Json | Set-Variable sdkCredentialsJSON
$sdkCredentialsMasked | ConvertTo-Json | Set-Variable sdkCredentialsJSONMasked
Write-Debug $sdkCredentialsJSONMasked

# Configure federation
if (!$SkipServicePrincipalFederation) {
    # Prepare federation subjects
    Write-Host "Preparing federation subjects..."
    $subjects = [System.Collections.ArrayList]@("repo:${RepositoryName}:pull_request")
    foreach ($branch in $BranchNames) {
        $subjects.Add("repo:${RepositoryName}:ref:refs/heads/${branch}") | Out-Null
    }
    if ($inRepository) {
        $currentBranch = $(git rev-parse --abbrev-ref HEAD)
        if (!$BranchNames -or !$BranchNames.Contains($currentBranch)) {
            $subjects.Add("repo:${RepositoryName}:ref:refs/heads/${currentBranch}") | Out-Null
        }
    }
    foreach ($tag in $TagNames) {
        $subjects.Add("repo:${RepositoryName}:ref:refs/tags/${tag}") | Out-Null
    }

    # Retrieve existing federation subjects
    Write-Host "Retrieving existing federation subjects for Service Principal with clientId '$appId'..."
    az ad app federated-credential list --id $appObjectId `
                                        --query [].subject `
                                        | ConvertFrom-Json `
                                        | Set-Variable federatedSubjects
    Write-Debug "federatedSubjects: $($federatedSubjects -join ',')"

    # Create federation subjects
    Write-Host "Creating federation subjects for Service Principal with clientId '$appId'..."
    foreach ($subject in $subjects) {
        if ($federatedSubjects -and $federatedSubjects.Contains($subject)) {
            Write-Verbose "Federation subject '$subject' already exists"
            continue
        }
        Write-Verbose "Creating federation subject '$subject'..."
        $federationName = ($subject -replace ":|/|_","-")

        Get-Content (Join-Path $PSScriptRoot "federated-identity-request-template.jsonc") | ConvertFrom-Json | Set-Variable request
        $request.description = "Created with $($MyInvocation.MyCommand.Name)"
        $request.name = $federationName
        $request.subject = $subject
        $request | Format-List | Out-String | Write-Debug

        # Pass JSON as file per best practice documented at:
        # https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md#double-quotes--are-lost
        $requestBodyFile = (New-TemporaryFile).FullName
        $request | ConvertTo-Json | Out-File $requestBodyFile
        Write-Debug "requestBodyFile: $requestBodyFile"

        az ad app federated-credential create --id $appObjectId --parameters $requestBodyFile
        if ($lastexitcode -ne 0) {
            Write-Error "Request to add subject '$subject' failed, exiting"
            exit
        }
    }
    Write-Host "Created federation subjects for GitHub repo '${RepositoryName}'"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "`nSetting GitHub $RepositoryName secrets AZURE_CLIENT_ID, AZURE_TENANT_ID & AZURE_SUBSCRIPTION_ID..."
    gh auth login -h $gitHost
    Write-Debug "Setting GitHub workflow secret AZURE_CLIENT_ID='$appId'..."
    gh secret set AZURE_CLIENT_ID -b $appId --repo $RepositoryName
    if ($CreateServicePrincipalPassword) {
        Write-Debug "Setting GitHub workflow secret AZURE_CLIENT_SECRET='$spPasswordMasked'..."
        gh secret set AZURE_CLIENT_SECRET -b $spPassword --repo $RepositoryName
    }
    if ($ConfigureAzureCredentialsJson) {
        Write-Debug "Setting GitHub workflow secret AZURE_CREDENTIALS='$sdkCredentialsJSONMasked'..."
        $sdkCredentialsJSON | gh secret set AZURE_CREDENTIALS --repo $RepositoryName
    }
    Write-Debug "Setting GitHub workflow secret AZURE_TENANT_ID='$TenantId'..."
    gh secret set AZURE_TENANT_ID -b $TenantId --repo $RepositoryName
    Write-Debug "Setting GitHub workflow secret AZURE_SUBSCRIPTION_ID='$SubscriptionId'..."
    gh secret set AZURE_SUBSCRIPTION_ID -b $SubscriptionId --repo $RepositoryName
} else {
    # Show workflow configuration information
    Write-Warning "`nGitHub CLI not found, configure secrets manually"
    Write-Host "Set GitHub workflow secret AZURE_CLIENT_ID='$appId' in $RepositoryName"
    if ($CreateServicePrincipalPassword) {
        Write-Host "Set GitHub workflow secret AZURE_CLIENT_SECRET='$spPasswordMasked' in $RepositoryName"
    }
    if ($ConfigureAzureCredentialsJson) {
        Write-Host "Set GitHub workflow secret AZURE_CREDENTIALS='$sdkCredentialsJSONMasked' in $RepositoryName"
    }
    Write-Host "Set GitHub workflow secret AZURE_TENANT_ID='$TenantId' in $RepositoryName"
    Write-Host "Set GitHub workflow secret AZURE_SUBSCRIPTION_ID='$SubscriptionId' in $RepositoryName"
}
Write-Host "`nGitHub repository:`n${repositoryUrl}"
Write-Host "`nConfigure workflow YAML as per the azure/login action documentation:`nhttps://github.com/marketplace/actions/azure-login"
Write-Host "`nService Principal in Azure Portal:`nhttps://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/${appId}/isMSAApp/"
Write-Host "`nAccess Control list on scope '$scope' in Azure Portal:`nhttps://portal.azure.com/#@${TenantId}/resource${scope}/users"
Write-Host "`nSecrets on GitHub web:`n${repositoryUrl}/settings/secrets/actions"
Write-Host "`n"