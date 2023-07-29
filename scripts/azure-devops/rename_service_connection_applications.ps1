#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Rename appliuations used by Azure DevOps service connections
.DESCRIPTION 
    Rename appliuations used by Azure DevOps service connections to include the organization, project and service connection name
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Organization")]
    [ValidateNotNullOrEmpty()]
    [string]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI),

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false)]
    [switch]
    $WhatIf=$false,

    [parameter(Mandatory=$false,HelpMessage="Reset application name to default")]
    [switch]
    $Reset=$false,

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)


# Get owned service connections using AAD tenant
$organizationName=($OrganizationUrl -split '/' | Select-Object -Index 3)
$userName=(az account show --query user.name -o tsv)
az devops service-endpoint list --project $Project `
                                --organization $OrganizationUrl `
                                --query "[?authorization.parameters.serviceprincipalid!=null && authorization.parameters.tenantid=='${TenantId}' && createdBy.uniqueName=='${userName}']" `
                                -o json `
                                | ConvertFrom-Json `
                                | Set-Variable -Name serviceConnections

$serviceConnections | Format-Table -AutoSize -Property Name | Out-String | Write-Debug

# Iterate through service connections
foreach ($serviceConnection in $serviceConnections) {
    # Get application
    Write-Verbose "Getting application '$($serviceConnection.authorization.parameters.serviceprincipalid)' for service connection '$($serviceConnection.name)'..."
    $application = $null
    az ad app list --app-id $serviceConnection.authorization.parameters.serviceprincipalid `
                   --query "[0]" `
                   -o json `
                   | ConvertFrom-Json `
                   | Set-Variable -Name application
    if (!$application) {
        Write-Host "Application for service connection '$($serviceConnection.name)' not found, the service connection is using a Managed Identity or may be orphaned"
        continue
    }
    $application | Format-List | Out-String | Write-Debug
    Write-Verbose "Application displayName: $($application.displayName)"

    # Determine default and new application names
    "{0}-{1}-{2}" -f $organizationName, $Project, $serviceConnection.data.subscriptionId `
                  | Set-Variable -Name defaultApplicationName
                  Write-Verbose "Default application name: ${defaultApplicationName}"
    if ($Reset) {
        $newApplicationName = $defaultApplicationName
    } else {
        "{0}-{1}-{2}" -f $organizationName, $Project, $serviceConnection.name `
                      | Set-Variable -Name newApplicationName
                      $newApplicationName -replace ' ', '' | Set-Variable -Name newApplicationName
    }
    Write-Verbose "New application name: ${newApplicationName}"

    # Determine whether app has been renamed
    $serviceConnection | Add-Member "oldApplicationName" $application.displayName
    if ($application.displayName -eq $newApplicationName) {
        Write-Host "Application for service connection '$($serviceConnection.name)' has already been renamed to '${newApplicationName}'"
        continue
    }

    # Rename app
    Write-Host "Renaming application $($application.displayName) to '${newApplicationName}'..."
    az ad app update --id $application.appId `
                     --display-name $newApplicationName
    $serviceConnection | Add-Member "newApplicationName" $newApplicationName
}

# List processed service connection identities
Write-Host "Service connections processed:"
$serviceConnections | Format-Table -AutoSize -Property Name, oldApplicationName, newApplicationName
