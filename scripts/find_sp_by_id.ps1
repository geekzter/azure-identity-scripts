#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    TODO
.DESCRIPTION 
    TODO
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$true,HelpMessage="Application/Client/Object/Principal ID")][guid]$Id,
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")][guid]$TenantId=$env:AZURE_TENANT_ID ?? $env:ARM_TENANT_ID
) 

Write-Debug $MyInvocation.line

. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Host "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

az ad sp list --filter "appId eq '$Id'" --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
if ($sp) {
    Write-Host "'$Id' is an Application ID"
} else {
    az ad sp show --id $Id 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Host "'$Id' is a Service Principal Object ID"
    }
}

if ($sp) {
    az ad app show --id $sp.appId | ConvertFrom-Json | Set-Variable app
} else {
    az ad app show --id $Id 2>$null | ConvertFrom-Json | Set-Variable app
    if ($app) {
        Write-Host "'$Id' is an Application Object ID"
        az ad sp list --filter "appId eq '$($app.appId)'" --query "[0]" | ConvertFrom-Json | Set-Variable sp
    } else {
        Write-Warning "Could not find Application or Service Principal objects with Application or Object ID '$Id'"
        exit
    }
}

Write-Host "Application:"
$app
Write-Host "Service Principal:"
$sp