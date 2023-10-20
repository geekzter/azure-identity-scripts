#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Create an AzureRM Service Connection in Azure DevOps

.DESCRIPTION 


.EXAMPLE

#> 
#Requires -Version 7.2

param ( 
    [parameter(Mandatory=$true,HelpMessage="Name of the Service Connection")]
    [string]
    $ServiceConnectionName,

    [parameter(Mandatory=$false)]
    [ValidateSet("ServicePrincipal", "WorkloadIdentityFederation")]
    [string]
    $ServiceConnectionScheme="WorkloadIdentityFederation",

    [parameter(Mandatory=$false)]
    [string]
    $ResourceGroupName,

    [parameter(Mandatory=$false)]
    [guid]
    [ValidateNotNullOrEmpty()]
    $SubscriptionId=($ARM_SUBSCRIPTION_ID ?? $env:AZURE_SUBSCRIPTION_ID),

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    [ValidateNotNullOrEmpty()]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI)
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)
$apiVersion = "7.1-preview.4"

#-----------------------------------------------------------
# Log in to Azure
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. You can get it here: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}
az account show -o json 2>$null | ConvertFrom-Json | Set-Variable account
if (!$account) {
    az login -o json | ConvertFrom-Json | Set-Variable account
}
az account show --subscription $SubscriptionId -o json 2>$null | ConvertFrom-Json | Set-Variable subscription
if (!$subscription) {
    Write-Warning "Subscription '$($SubscriptionId)' not found, exiting"
}
$ServiceConnectionScope = "/subscriptions/${SubscriptionId}"
if ($ResourceGroupName) {
    $ServiceConnectionScope = "${ServiceConnectionScope}/resourceGroups/${ResourceGroupName}"
}
# Log in to Azure & Azure DevOps
$OrganizationUrl = $OrganizationUrl.ToString().Trim('/')
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 `
                            --query "accessToken" `
                            --output tsv `
                            | Set-Variable accessToken
if (!$accessToken) {
    Write-Error "$(subscription.user.name) failed to get access token for Azure DevOps"
    exit 1
}
if (!(az extension list --query "[?name=='azure-devops'].version" -o tsv)) {
    Write-Host "Adding Azure CLI extension 'azure-devops'..."
    az extension add -n azure-devops -y -o none
}
$accessToken | az devops login --organization $OrganizationUrl
if ($lastexitcode -ne 0) {
    Write-Error "$($subscription.user.name) failed to log in to Azure DevOps organization '${OrganizationUrl}'"
    exit $lastexitcode
}

# Check whether project exists
az devops project show --project $Project --organization $OrganizationUrl --query id -o tsv | Set-Variable projectId
if (!$projectId) {
    Write-Error "Project '${Project}' not found in organization '${OrganizationUrl}"
    exit 1
}
              
# Prepare service connection REST API request body
Write-Verbose "Creating / updating service connection '${ServiceConnectionName}'..."
Get-Content -Path (Join-Path $PSScriptRoot automaticServiceEndpointRequest.json) `
            | ConvertFrom-Json `
            | Set-Variable serviceEndpointRequest

$serviceEndpointDescription = "Created by $($MyInvocation.MyCommand.Name) with scope ${ServiceConnectionScope}"
$serviceEndpointRequest.authorization.parameters.tenantId = $subscription.tenantId
$serviceEndpointRequest.authorization.parameters.scope = $ServiceConnectionScope
$serviceEndpointRequest.authorization.scheme = $ServiceConnectionScheme
$serviceEndpointRequest.data.subscriptionId = $SubscriptionId
$serviceEndpointRequest.data.subscriptionName = $subscription.name
$serviceEndpointRequest.description = $serviceEndpointDescription
$serviceEndpointRequest.name = $ServiceConnectionName
$serviceEndpointRequest.serviceEndpointProjectReferences[0].name = $ServiceConnectionName
$serviceEndpointRequest.serviceEndpointProjectReferences[0].projectReference.id = $projectId
$serviceEndpointRequest.serviceEndpointProjectReferences[0].projectReference.name = $Project
$serviceEndpointRequest | ConvertTo-Json -Depth 4 | Set-Variable serviceEndpointRequestBody
Write-Debug "Service connection request body: `n${serviceEndpointRequestBody}"

$apiUri = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints?api-version=${apiVersion}"
Write-Debug "POST ${apiUri}"
Invoke-RestMethod -Uri $apiUri `
                  -Method POST `
                  -Body $serviceEndpointRequestBody `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  | Set-Variable serviceEndpoint

$serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
if (!$serviceEndpoint) {
    Write-Error "Failed to create / update service connection '${ServiceConnectionName}'"
    exit 1
}
$serviceConnectionGetApiUrl = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints/$($serviceEndpoint.id)?api-version=${apiVersion}"
Write-Host "Waiting for service connection '${ServiceConnectionName}' with id $($serviceEndpoint.id) to be ready..."
while ($serviceEndpoint.operationStatus.state -eq "InProgress") {
    Write-Debug "GET ${serviceConnectionGetApiUrl}"
    $serviceEndpoint = Invoke-RestMethod -Uri $serviceConnectionGetApiUrl `
                                         -Method GET `
                                         -ContentType 'application/json' `
                                         -Authentication Bearer `
                                         -Token (ConvertTo-SecureString $accessToken -AsPlainText)
    $serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug

    Start-Sleep -Seconds 1
}
if ($serviceEndpoint.operationStatus.statusMessage) {
    Write-Verbose $serviceEndpoint.operationStatus.statusMessage
}

if (!$serviceEndpoint.isReady) {
    Write-Error "Service Connection '${ServiceConnectionName}' with id $($serviceEndpoint.id) is in state '$($serviceEndpoint.operationStatus.state)'. $($serviceEndpoint.operationStatus.statusMessage)"
    $serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Warning
    exit 1
}

Write-Host "Service connection '${ServiceConnectionName}' created:"
Write-Debug "Service connection data:"
$serviceEndpoint.data | Format-List | Out-String | Write-Debug
Write-Debug "Service connection authorization parameters:"
$serviceEndpoint.authorization.parameters | Format-List | Out-String | Write-Debug

$serviceEndpoint | Select-Object -Property authorization, data, id, name, description, type, createdBy `
                 | ForEach-Object { 
                 $_.createdBy = $_.createdBy.uniqueName
                 $_ | Add-Member -NotePropertyName clientId -NotePropertyValue $_.authorization.parameters.serviceprincipalid
                 $_ | Add-Member -NotePropertyName creationMode -NotePropertyValue $_.data.creationMode
                 $_ | Add-Member -NotePropertyName scheme -NotePropertyValue $_.authorization.scheme
                 $_ | Add-Member -NotePropertyName scopeLevel -NotePropertyValue $_.data.scopeLevel
                 $_ | Add-Member -NotePropertyName subscriptionName -NotePropertyValue $_.data.subscriptionName
                 $_ | Add-Member -NotePropertyName subscriptionId -NotePropertyValue $_.data.subscriptionId
                 $_ | Add-Member -NotePropertyName tenantid -NotePropertyValue $_.authorization.parameters.tenantid
                 $_ | Add-Member -NotePropertyName workloadIdentityFederationSubject -NotePropertyValue $_.authorization.parameters.workloadIdentityFederationSubject
                 $_
                 } `
                 | Select-Object -ExcludeProperty authorization, data
                 | Format-List
