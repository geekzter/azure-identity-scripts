#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find a Service Principal
.DESCRIPTION 
    Find a Service Principal by (object/principal) id, service principal name, application/client id, application name, user assigned identity resource id, etc
.EXAMPLE
    ./find_service_principal.ps1 12345678-1234-1234-abcd-1234567890ab
.EXAMPLE
    ./find_service_principal.ps1 my-service-principal-name
.EXAMPLE
    ./find_service_principal.ps1 /subscriptions/12345678-1234-1234-abcd-1234567890ab/resourcegroups/my-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my-user-assigned-identity
.EXAMPLE
    ./find_service_principal.ps1 "https://identity.azure.net/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx="
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
function Find-ApplicationByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    az ad app list --display-name $Name --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable app
    if ($app) {
        Write-Host "'$Name' is an Application Display Name"
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
function Find-ServicePrincipalByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    az ad sp show --id $Name 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Host "'$Name' is name or ID"
    } else {
        az ad sp list --show-mine --query "[?contains(servicePrincipalNames,'$Name')]" --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
        if ($sp) {
            Write-Host "'$Name' is in servicePrincipalNames[]"
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
        Write-Verbose "'$IdOrName' is a GUID"
        Find-ServicePrincipalByGUID -Id $IdOrName | Set-Variable sp
        if (!$sp) {
            Find-ApplicationByGUID -Id $IdOrName | Set-Variable app
            if ($app) {
                az ad sp list --filter "appId eq '$($app.appId)'" --query "[0]" | ConvertFrom-Json | Set-Variable sp
            } else {
                Write-Warning "Could not find Application or Service Principal objects with Application or Object ID '$IdOrName'"
                exit
            }
        }
        break
    }
    # Match User-assigned Identity Resource ID
    "/subscriptions/(.)+/resourcegroups/(.)+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/(.)+" {
        Write-Verbose "'$IdOrName' is a User-assigned Identity Resource ID"
        Find-ManagedIdentityByResourceID -Id $IdOrName | Set-Variable mi
        if ($mi) {
            Find-ServicePrincipalByGUID -Id $mi.clientId | Set-Variable sp
        } else {
            Write-Warning "Could not find Managed Identity with Resource ID '$IdOrName'"
            exit
        }
        break
    }
    # Match generic Resource ID (System-assigned Identity)
    "/subscriptions/(.)+/resourcegroups/(.)+/(.)+/(.)+" {
        Write-Verbose "'$IdOrName' is a Resource ID"
        az resource show --ids $IdOrName --query "identity.principalId" -o tsv 2>$null | Set-Variable principalId
        if ($principalId) {
            Find-ServicePrincipalByGUID -Id $principalId | Set-Variable sp
        } else {
            Write-Warning "Could not find System-assigned Identity with Resource ID '$IdOrName'"
            exit
        }
        break
    }
    # Match Name or URL
    "^[\w\-\/\:\.]+$" {
        Find-ApplicationByName -Name $IdOrName | Set-Variable app
        if ($app) {
            az ad sp list --filter "appId eq '$($app.appId)'" --query "[0]" | ConvertFrom-Json | Set-Variable sp
        } else {
            Find-ServicePrincipalByName -Name $IdOrName | Set-Variable sp
        }
        break
    }
    default {
        Write-Output "$($PSStyle.Formatting.Error)'$IdOrName' is not a valid GUID, Name or Resource ID, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
}

if (!$app -and $sp -and ($sp.servicePrincipalType -ieq "Application")) {
    az ad app show --id $sp.appId | ConvertFrom-Json | Set-Variable app
}
if ($app) {
    Write-Host "Found Application '$($app.displayName)' with ID '$($app.appId)'"
    $app
}
if ($sp) {
    Write-Host "Found Service Principal '$($sp.displayName)' of type '$($sp.servicePrincipalType)' with ID '$($sp.appId)'"
    $sp
    #BUG: Unable to list credentials https://github.com/Azure/azure-cli/issues/21195
}