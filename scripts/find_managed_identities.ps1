#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find a Managed Identities
.DESCRIPTION 
    Find a Managed Identities using Microsoft Graph API
.EXAMPLE
    ./find_managed_identities.ps1 mmyalias
.EXAMPLE
    ./find_managed_identities.ps1 -Search term -ManagedIdentityType UserCreated
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)]
    [ValidateNotNull()]
    [string]$Search,

    [parameter(Mandatory=$false)]
    [ValidateSet("UserCreated", "SystemCreated", "Any")]
    [string]$ManagedIdentityType="Any",

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

if (!$Search) {
    # Take users alias as search term
    (az account show --query "user.name" -o tsv) -split '@' | Select-Object -First 1 | Set-Variable Search
    if (!$Search) {
        Write-Warning "Search term not provided, exiting"
        exit 1
    }
}
Write-Host "Searching for Managed Identities of type '${ManagedIdentityType}' matching '${Search}'..."

# Write-Verbose "Microsoft Graph API results starting with '${Search}':"
Find-ManagedIdentitiesByNameMicrosoftGraph -StartsWith $Search | Set-Variable msftGraphObjects
# $msftGraphObjects | Format-Table -AutoSize | Out-String | Write-Verbose

# Write-Verbose "Azure Resource Graph results matching '${Search}':"
Find-ManagedIdentitiesByNameAzureResourceGraph -Search $Search | Set-Variable armResources
# $armResources | Format-Table -AutoSize | Out-String | Write-Verbose

[system.collections.arraylist]$allObjects = @()
if ($msftGraphObjects -is [array]) {
    $allObjects = $msftGraphObjects
} else {
    $allObjects = @($msftGraphObjects)
}
if ($armResources -is [array]) {
    $allObjects.AddRange($armResources)
} else {
    $allObjects.Add($armResources) | Out-Null
}
Write-Host "User-created Managed Identities matching search term '${Search}':"
$allObjects | Sort-Object -Property name -Unique | Format-Table -AutoSize
