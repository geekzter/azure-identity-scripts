#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find a Managed Identities
.DESCRIPTION 
    Find a Managed Identities using Microsoft Graph API
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)]
    [ValidateNotNull()]
    [string]$Search,

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")]
    [ValidateNotNull()]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

function Find-ManagedIdentityByNameMicrosoftGraph (
    [parameter(Mandatory=$true)][string]$StartsWith
) {
# az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=startswith(displayName,'ericvan') and servicePrincipalType eq 'ManagedIdentity'&`$select=appId,displayName,alternativeNames&`$orderBy=displayName" --headers ConsistencyLevel=eventual --query "value[?contains(alternativeNames[1],'Microsoft.ManagedIdentity')] | [].{name:displayName,appId:appId,resourceId:alternativeNames[1]}" | ConvertFrom-Json
az rest --method get `
            --url "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=startswith(displayName,'ericvan') and servicePrincipalType eq 'ManagedIdentity'&`$select=appId,displayName,alternativeNames&`$orderBy=displayName" `
            --headers ConsistencyLevel=eventual `
            --query "value[?contains(alternativeNames[1],'Microsoft.ManagedIdentity')] | [].{name:displayName,appId:appId,resourceId:alternativeNames[1]}" `
            -o json `
            | ConvertFrom-Json `
            | Select-Object -Property name,appId,resourceId
}

function Find-ManagedIdentityByNameAzureResourceGraph (
    [parameter(Mandatory=$true)][string]$Search
) {
    az graph query -q "Resources | where type =~ 'Microsoft.ManagedIdentity/userAssignedIdentities' and name contains '${Search}' | extend sp = parse_json(properties) | project name=name,appId=sp.clientId,resourceId=id | order by name asc" `
                   -a `
                   --query "data" `
                   -o json `
                   | ConvertFrom-Json `
                   | Select-Object -Property name,appId,resourceId
}

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

if (!$Search) {
    # Take users alias as search term
    (az account show --query "user.name" -o tsv) -split '@' | Select-Object -First 1 | Set-Variable Search
}

Write-Host "Microsoft Graph API results"
Find-ManagedIdentityByNameMicrosoftGraph -StartsWith $Search | Set-Variable msftGraphObjects
$msftGraphObjects | Format-Table -AutoSize

Write-Host "Azure Resource Graph results"
Find-ManagedIdentityByNameAzureResourceGraph -Search $Search | Set-Variable armResources
$armResources | Format-Table -AutoSize

$allObjects = $msftGraphObjects + $armResources
Write-Host "All results"
$allObjects | Sort-Object -Property name -Unique | Format-Table -AutoSize


