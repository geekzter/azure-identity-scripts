#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    List Azure DevOps Service Connections
.DESCRIPTION 
    Use the Azure CLI to find Azure DevOps Service Connections by organization & project
#>
#Requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'name')]
param ( 
    [parameter(Mandatory=$false,ParameterSetName="app")]
    [guid[]]
    $AppId,

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
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI),

    [parameter(Mandatory=$false)]
    [ValidateSet('List', 'Table')]
    [string]
    $Format='Table'
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)
$apiVersion = "7.1"
if ($AppId) {
    $AppId | Foreach-Object {$_.ToString().ToLower()} | Set-Variable AppId
}

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
$accessToken | az devops login --organization $OrganizationUrl
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

$getApiUrl = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints?type=azurerm&includeFailed=true&includeDetails=true&api-version=${apiVersion}"
az rest --resource 499b84ac-1321-427f-aa17-267ca6975798 -u "${getApiUrl} " -m GET --query "sort_by(value[?authorization.scheme=='ServicePrincipal' && data.creationMode=='Automatic' && !(isShared && serviceEndpointProjectReferences[0].projectReference.name!='${Project}')],&name)" -o json `
        | Tee-Object -Variable rawResponse `
        | ConvertFrom-Json `
        | Tee-Object -Variable serviceEndpoints `
        | Format-List | Out-String | Write-Debug
if (!$serviceEndpoints -or ($serviceEndpoints.count-eq 0)) {
    Write-Warning "No convertible service connections found"
    exit 1
}

$serviceEndpoints | ForEach-Object {
    "https://portal.azure.com/{0}/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/{1}" -f $_.authorization.parameters.tenantId, $_.authorization.parameters.servicePrincipalId | Set-Variable applicationPortalLink
    $_ | Add-Member -NotePropertyName applicationPortalLink -NotePropertyValue $applicationPortalLink
    "{0}/{1}/_settings/adminservices?resourceId={2}" -f $OrganizationUrl, $_.serviceEndpointProjectReferences[0].projectReference.id, $_.id | Set-Variable serviceConnectionPortalLink
    $_ | Add-Member -NotePropertyName serviceConnectionPortalLink -NotePropertyValue $serviceConnectionPortalLink
    $_ | Add-Member -NotePropertyName authorizationScheme -NotePropertyValue $_.authorization.scheme
    $_ | Add-Member -NotePropertyName appId -NotePropertyValue $_.authorization.parameters.servicePrincipalId.ToLower()
    
    $_
} | Where-Object { 
    # We already check federation on organization/project, so we can ignore it here
    !$AppId -or ($_.appId -in $AppId)
} | Set-Variable filteredServiceEndpoints

switch ($Format) {
    'List' {
        $filteredServiceEndpoints | Format-List 
    }
    'Table' {
        $filteredServiceEndpoints | Format-Table -AutoSize -Property name, authorizationScheme, appId
    }
}
$filteredServiceEndpoints | ForEach-Object {
    $_.appId
} | Set-Variable matchedAppIds
Write-Host "Matched AppIds: $($matchedAppIds -join ', ')"
$AppId | Where-Object {
           $_ -notin $matchedAppIds
         }
       | Set-Variable unmatchedAppIds
if ($unmatchedAppIds) {
    Write-Warning "Unmatched AppIds: $($unmatchedAppIds -join ', ')"
}
