#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS 
    Configures Service Management Reference on Entra ID application
.EXAMPLE
    ./add_app_itsm_information.ps1 -AppId 00000000-0000-0000-00000000000000000 -ServiceManagementReferenceId 00000000-0000-0000-00000000000000000
.EXAMPLE
    ./add_app_itsm_information.ps1 -ServiceManagementReferenceId 00000000-0000-0000-00000000000000000 -CoOwner johndoe@fabrikam.com -Force
#>
param ( 
    [parameter(Mandatory=$false)]
    [guid]
    $AppId,
    
    [parameter(Mandatory=$false)]
    [string]
    $CoOwner,

    [parameter(Mandatory=$false)]
    [switch]
    $Force=$false,

    [parameter(Mandatory=$true)]
    [guid]
    $ServiceManagementReferenceId,

    [parameter(Mandatory=$false,HelpMessage="Entra ID tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

if ($AppId) {
    az ad app show --id $AppId `
                   -o json `
                   | ConvertFrom-Json `
                   | Set-Variable -Name App
    $apps = @($app)
    $app | Format-List | Out-String | Write-Verbose
} else {
    $query = $Force ? "[]" : "[?serviceManagementReference!='${ServiceManagementReferenceId}']"
    az ad app list --show-mine `
                   -o json `
                   --query "${query}" `
                   | ConvertFrom-Json `
                   | Set-Variable -Name Apps
    $apps | Format-Table -Property id,displayName -AutoSize | Out-String | Write-Verbose
}

if ($CoOwner) {
    az ad user show --id $CoOwner `
                    -o tsv `
                    --query id `
                    | Set-Variable -Name coOwnerId
}

foreach ($app in $apps) {
    if (!$Force -and $app.serviceManagementReference) {
        Write-Warning "Service Management Reference already on app '$($app.displayName)' with id '$($app.id)' already set to '$($app.serviceManagementReference)'. Skipping Service Management Reference update."
        continue
    }
    Write-Verbose "Adding Service Management Reference to app '$($app.displayName)' with id '$($app.id)'..."
    az ad app update --id $app.id `
                     --set serviceManagementReference=$ServiceManagementReferenceId `
                     -o none

    if ($coOwnerId) {
        Write-Verbose "Adding co-owner '$CoOwner' to app '$($app.displayName)' with id '$($app.id)'..."
        az ad app owner add --id $app.id `
                            --owner-object-id $coOwnerId `
                            -o none
    }
}

if ($AppId) {
    az ad app show --id $AppId `
                   -o json `
                   | ConvertFrom-Json `
                   | Format-List
} else {
    Write-Host "Owned applications:"
    az ad app list --show-mine `
                   -o json `
                   | ConvertFrom-Json `
                   | Set-Variable -Name Apps
    $apps | Format-Table -Property id,displayName,serviceManagementReference -AutoSize 
}
