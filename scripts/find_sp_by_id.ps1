#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    TODO
.DESCRIPTION 
    TODO
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$true,HelpMessage="Application/Client/Object/Principal ID/Resource ID")][string]$IdOrName,
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")][guid]$TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

function Find-ApplicationByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    az ad app show --id $Id 2>$null | ConvertFrom-Json | Set-Variable app
    if ($app) {
        Write-Host "'$Id' is an Application Object ID"
        return $app
    } else {
        return $null
    }
}
function Find-ManagedIdentityByResourceID (
    [parameter(Mandatory=$true)][string]$Id
) {
    az identity show --ids $id 2>$null | ConvertFrom-Json | Set-Variable mi

    return $mi
}
function Find-ServicePrincipalByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    az ad sp list --filter "appId eq '$Id'" --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Host "'$Id' is an Application ID"
    } else {
        az ad sp show --id $Id 2>$null | ConvertFrom-Json | Set-Variable sp
        if ($sp) {
            Write-Host "'$Id' is a Service Principal Object ID"
        }
    }

    return $sp
}
Write-Debug $MyInvocation.line

. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Host "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

# Parse input
switch -regex ($IdOrName) {
    # Match GUID
    "(?im)^[{(]?[0-9A-F]{8}[-]?(?:[0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?$" {

        Find-ServicePrincipalByGUID -Id $IdOrName | Set-Variable sp
        if ($sp) {
            if ($sp.servicePrincipalType -ine "ManagedIdentity") {
                az ad app show --id $sp.appId | ConvertFrom-Json | Set-Variable app
            }
        } else {
            Find-ApplicationByGUID -Id $IdOrName | Set-Variable app
            if ($app) {
                az ad sp list --filter "appId eq '$($app.appId)'" --query "[0]" | ConvertFrom-Json | Set-Variable sp
            } else {
                Write-Warning "Could not find Application or Service Principal objects with Application or Object ID '$Id'"
                exit
            }
        }
        break
    }
    # Match Resource ID
    "/subscriptions/(.)+/resourcegroups/(.)+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/(.)+" {
        Write-Host "'$IdOrName' is a Resource ID"
        Find-ManagedIdentityByResourceID -Id $IdOrName | Set-Variable mi
        if ($mi) {
            Find-ServicePrincipalByGUID -Id $mi.clientId | Set-Variable sp
        } else {
            Write-Warning "Could not find Managed Identity with Resource ID '$Id'"
            exit
        }
        break
    }
    "^.+$" {
        Write-Output "$($PSStyle.Formatting.Error)'$IdOrName' is not a valid ID, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
    "" {
        Write-Output "$($PSStyle.Formatting.Error)'$IdOrName' is empty, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
    default {
        Write-Output "$($PSStyle.Formatting.Error)'$IdOrName' is not a valid GUID or Resource ID, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
}

if ($app) {
    Write-Host "Found Application '$($app.displayName)' with ID '$($app.appId)'"
    $app
}
if ($sp) {
    Write-Host "Found Service Principal '$($sp.displayName)' of type '$($sp.servicePrincipalType)' with ID '$($sp.appId)'"
    $sp
}