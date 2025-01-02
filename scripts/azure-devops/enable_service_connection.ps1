#!/usr/bin/env pwsh
#Requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'name')]
param ( 
    [parameter(Mandatory=$false,ParameterSetName="id",HelpMessage="Id of the Service Connection")]
    [guid]
    $ServiceConnectionId,

    [parameter(Mandatory=$false,ParameterSetName="name",HelpMessage="Name of the Service Connection")]
    [string]
    $ServiceConnectionName,

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
$apiVersion = "7.1"

#-----------------------------------------------------------
# Log in to Azure
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. You can get it here: http://aka.ms/azure-cli"
    exit 1
}
az account show -o json 2>$null | ConvertFrom-Json | Set-Variable account
if (!$account) {
    az login --allow-no-subscriptions -o json | ConvertFrom-Json | Set-Variable account
}
# Log in to Azure & Azure DevOps
$OrganizationUrl = $OrganizationUrl.ToString().Trim('/')
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 `
                            --query "accessToken" `
                            --output tsv `
                            | Set-Variable accessToken
if (!$accessToken) {
    Write-Error "$(account.user.name) failed to get access token for Azure DevOps"
    exit 1
}
if (!(az extension list --query "[?name=='azure-devops'].version" -o tsv)) {
    Write-Host "Adding Azure CLI extension 'azure-devops'..."
    az extension add -n azure-devops -y -o none
}
if ($lastexitcode -ne 0) {
    Write-Error "$($account.user.name) failed to log in to Azure DevOps organization '${OrganizationUrl}'"
    exit $lastexitcode
}

#-----------------------------------------------------------
# Check parameters
az devops project show --project "${Project}" --organization $OrganizationUrl --query id -o tsv | Set-Variable projectId
if (!$projectId) {
    Write-Error "Project '${Project}' not found in organization '${OrganizationUrl}"
    exit 1
}

#-----------------------------------------------------------
# Retrieve the service connection
$baseEndpointUrl = "${OrganizationUrl}/${projectId}/_apis/serviceendpoint/endpoints"
if ($ServiceConnectionId) {
    $getApiUrl = "${baseEndpointUrl}/${ServiceConnectionId}?includeDetails=true&api-version=${apiVersion}"
} elseif ($ServiceConnectionName) {
    $getApiUrl = "${baseEndpointUrl}?endpointNames=${ServiceConnectionName}&type=azurerm&includeFailed=false&includeDetails=true&api-version=${apiVersion}"
} else {
    $getApiUrl = "${baseEndpointUrl}?authSchemes=ServicePrincipal&type=azurerm&includeFailed=false&includeDetails=true&api-version=${apiVersion}"
}
Write-Debug "GET $getApiUrl"
Invoke-RestMethod -Uri $getApiUrl `
                  -Method GET `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  -StatusCodeVariable httpStatusCode `
                  | Set-Variable serviceEndpointResponse
if ($ServiceConnectionId) {
    $serviceEndpoint = $serviceEndpointResponse
} else {
    $serviceEndpointResponse | Select-Object -ExpandProperty value -First 1 `
                             | Set-Variable serviceEndpoint
}
$serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
if (!$serviceEndpoint.isDisabled) {
    Write-Host "Service Connection '$($serviceEndpoint.name)' ($($serviceEndpoint.id)) is already enabled"
    exit 0
}

#-----------------------------------------------------------
# Enable the service connection
$serviceEndpoint.isDisabled = $false
$serviceEndpoint | ConvertTo-Json -Depth 4 -Compress | Set-Variable serviceEndpointRequest
$putApiUrl = "${baseEndpointUrl}/$($serviceEndpoint.id)?api-version=${apiVersion}"
Write-Debug "PUT $putApiUrl"

Invoke-RestMethod -Uri $putApiUrl `
                  -Method PUT `
                  -Body $serviceEndpointRequest `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  -StatusCodeVariable httpStatusCode `
                  | Set-Variable serviceEndpoint

$serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
$serviceEndpoint | Format-List