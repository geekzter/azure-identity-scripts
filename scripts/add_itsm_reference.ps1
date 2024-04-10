#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS 
    Confugures Service Management Reference on Entra ID application
#>
param ( 
    [parameter(Mandatory=$false)]
    [guid]
    $AppId,
    
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
    az ad app list --show-mine `
                   -o json `
                   --query "[?serviceManagementReference!='${ServiceManagementReferenceId}']" `
                   | ConvertFrom-Json `
                   | Set-Variable -Name Apps
    $apps | Format-Table -Property id,displayName -AutoSize | Out-String | Write-Verbose
}

foreach ($app in $apps) {
    if ($app.serviceManagementReference) {
        Write-Warning "Service Management Reference already on app '$($app.displayName)' with id '$($app.id)' already set to '$($app.serviceManagementReference)'. Skipping..."
        continue
    }
    Write-Verbose "Adding Service Management Reference to app '$($app.displayName)' with id '$($app.id)'..."
    az ad app update --id $app.id `
                     --set serviceManagementReference=$ServiceManagementReferenceId `
                     -o none
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
