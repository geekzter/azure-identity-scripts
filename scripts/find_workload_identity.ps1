#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find a Service Principal or Managed Identity
.DESCRIPTION 
    Workload Identity is the umbrella term for both Service Principal and Managed Identity. This script will find a Service Principal or Managed Identity by various means.
    Find an identity by (object/principal) id, service principal name, application/client id, application name, user assigned identity resource id, etc
.EXAMPLE
    ./find_workload_identity.ps1 12345678-1234-1234-abcd-1234567890ab
.EXAMPLE
    ./find_workload_identity.ps1 my-service-principal-name
.EXAMPLE
    ./find_workload_identity.ps1 /subscriptions/12345678-1234-1234-abcd-1234567890ab/resourcegroups/my-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my-user-assigned-identity
.EXAMPLE
    ./find_workload_identity.ps1 "https://identity.azure.net/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx="
.EXAMPLE
    ./find_workload_identity.ps1 "https://VisualStudio/SPN12345678-1234-1234-abcd-1234567890ab"
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$true,HelpMessage="Application/Client/Object/Principal ID/Resource ID")]
    [ValidateNotNullOrEmpty()]
    [string]
    $IdOrName,

    [parameter(Mandatory=$false)]
    [bool]
    $FindApplication=$true,
    
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
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
            Find-ServicePrincipalByGUID -Id $mi.principalId | Set-Variable sp
        } else {
            Write-Warning "Could not find Managed Identity with Resource ID '$IdOrName'"
            exit
        }
        break
    }
    # Match generic Resource ID (System-assigned Identity)
    "/subscriptions/(.)+/resourcegroups/(.)+/(.)+/(.)+" {
        Write-Verbose "'$IdOrName' is a Resource ID"
        Find-ManagedIdentityByResourceID -Id $IdOrName | Set-Variable mi
        if ($mi) {
            Find-ServicePrincipalByGUID -Id $mi.principalId | Set-Variable sp
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
        if (!$sp) {
            Write-Warning "Could not find Service Principal with name '$IdOrName'"
            exit
        }
        break
    }
    default {
        Write-Output "$($PSStyle.Formatting.Error)'$IdOrName' is not a valid GUID, Name or Resource ID, exiting$($PSStyle.Reset)" | Write-Warning
        exit
    }
}

if ($FindApplication -and !$app -and $sp -and ($sp.servicePrincipalType -ieq "Application")) {
    az ad app show --id $sp.appId | ConvertFrom-Json | Set-Variable app
}
if ($app) {
    Write-Host "Found Application '$($app.displayName)' with appId '$($app.appId)'"
    $app | Format-List
}
if ($sp) {
    Write-Host "Found Service Principal '$($sp.displayName)' of type '$($sp.servicePrincipalType)' with appId '$($sp.appId)'"
    $sp | Format-List
}