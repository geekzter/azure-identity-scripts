#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Add Azure DevOps Service Connection(s) to Entra ID Security Group
.DESCRIPTION 
    Use the Azure CLI to find Azure DevOps Service Connections by organization & project and add them to an Entra ID Security Group
#>
#Requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'name')]
param ( 
    [parameter(Mandatory=$false,ParameterSetName="name",HelpMessage="Name of the Service Connection")]
    [string]
    $ServiceConnectionNameOrPattern,

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    [ValidateNotNullOrEmpty()]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI),

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID ?? [guid]::Empty),

    [parameter(Mandatory=$false,HelpMessage="Group object id")]
    [guid]
    $GroupObjectId,

    [parameter(Mandatory=$false)]
    [ValidateSet('List', 'Table')]
    [string]
    $Format='List'
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
Login-Az -TenantId ([ref]$TenantId)
# az account show -o json 2>$null | ConvertFrom-Json | Set-Variable account
# if ($TenantId -and ($TenantId -ne [guid]::Empty)) {
#     if (!$account -or ($account.tenantId -ine $TenantId)) {
#         az login --allow-no-subscriptions -o json --tenant $TenantId | ConvertFrom-Json | Set-Variable account
#     }
# } else {
#     if (!$account) {
#         az login --allow-no-subscriptions -o json | ConvertFrom-Json | Set-Variable account
#     }
# }
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
# Retrieve the service connection(s)

$getApiUrl = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints?type=azurerm&includeFailed=true&includeDetails=true&api-version=${apiVersion}"
if ($TenantId -and ($TenantId -ne [guid]::Empty)) {
    $query = "sort_by(value[?(authorization.parameters.serviceprincipalid!=null || authorization.parameters.servicePrincipalId!=null) && (authorization.parameters.tenantid=='${TenantId}' || authorization.parameters.tenantId=='${TenantId}')],&name)"
} else {
    $query = "sort_by(value[],&name)"
}
az rest --resource 499b84ac-1321-427f-aa17-267ca6975798 -u "${getApiUrl} " -m GET --query "${query}" -o json `
        | Tee-Object -Variable rawResponse `
        | ConvertFrom-Json `
        | Tee-Object -Variable serviceEndpoints `
        | Format-List | Out-String | Write-Debug
if (!$serviceEndpoints -or ($serviceEndpoints.count-eq 0)) {
    Write-Warning "No service connections found"
    exit 1
}

[system.collections.arraylist]$filteredServiceEndpoints = @()
foreach ($serviceEndpoint in $serviceEndpoints) {
    if ($ServiceConnectionNameOrPattern -and ($serviceEndpoint.name -notmatch $ServiceConnectionNameOrPattern)) {
        Write-Verbose "Skipping service connection '$($serviceEndpoint.name)'"
        continue
    }

    $appId = $serviceEndpoint.authorization.parameters.servicePrincipalId
    az ad sp show --id $appId | ConvertFrom-Json | Set-Variable sp
    if (!$sp) {
        Write-Warning "Service Principal with appId '{$appId}' for '$($serviceEndpoint.name)' does not exist in Entra ID"
        continue
    }
    az ad group member add --group $GroupObjectId --member-id $sp.id

    $filteredServiceEndpoints.Add($serviceEndpoint) | Out-Null
}

$serviceEndpoints | ForEach-Object {
    "https://portal.azure.com/{0}/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/{1}" -f $_.authorization.parameters.tenantId, $_.authorization.parameters.servicePrincipalId | Set-Variable applicationPortalLink
    $_ | Add-Member -NotePropertyName applicationPortalLink -NotePropertyValue $applicationPortalLink
    "{0}/{1}/_settings/adminservices?resourceId={2}" -f $OrganizationUrl, $_.serviceEndpointProjectReferences[0].projectReference.id, $_.id | Set-Variable serviceConnectionPortalLink
    $_ | Add-Member -NotePropertyName serviceConnectionPortalLink -NotePropertyValue $serviceConnectionPortalLink
    $_ | Add-Member -NotePropertyName authorizationScheme -NotePropertyValue $_.authorization.scheme
    $_ | Add-Member -NotePropertyName appId -NotePropertyValue $_.authorization.parameters.servicePrincipalId?.ToLower()
    
    $_
} | Set-Variable filteredServiceEndpoints

switch ($Format) {
    'List' {
        $filteredServiceEndpoints | Format-List 
    }
    'Table' {
        $filteredServiceEndpoints | Format-Table -AutoSize -Property name, authorizationScheme, appId
    }
}