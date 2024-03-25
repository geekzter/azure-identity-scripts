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
    [string[]]
    $Project=@($env:SYSTEM_TEAMPROJECT),

    [parameter(Mandatory=$false)]
    [switch]
    $WhatIf=$false,

    [parameter(Mandatory=$false,HelpMessage="Reset application name to default")]
    [switch]
    $Reset=$false,

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID ?? [guid]::Empty)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)


# Get org & user information
$organizationName=($OrganizationUrl -split '/' | Select-Object -Index 3)
$OrganizationUrl -replace "/*$", "" | Set-Variable -Name OrganizationUrl
$userName=(az account show --query user.name -o tsv)

foreach ($azdoProject in $Project) {
    # Get owned service connections using AAD tenant

    az devops service-endpoint list --project $azdoProject `
                                --organization $OrganizationUrl `
                                --query "[?authorization.parameters.serviceprincipalid!=null && authorization.parameters.tenantid=='${TenantId}' && createdBy.uniqueName=='${userName}']" `
                                -o json `
                                | ConvertFrom-Json `
                                | Set-Variable -Name serviceConnections

    $serviceConnections | Format-Table -AutoSize -Property Name | Out-String | Write-Debug

    # Iterate through service connections
    "Processing service connections referencing an AAD application in {0}/{1}/_settings/adminservices created by {2}..." -f $OrganizationUrl, [uri]::EscapeDataString($azdoProject), $userName | Write-Host
    foreach ($serviceConnection in $serviceConnections) {
        # Do not rename service connections shared from another project
        "{0}/{1}/_settings/adminservices?resourceId={2}" -f $OrganizationUrl, $serviceConnection.serviceEndpointProjectReferences[0].projectReference.name, $serviceConnection.id | Set-Variable originalServiceEndpointUrl
        if ($serviceConnection.isShared) {
            if ($serviceConnection.serviceEndpointProjectReferences[0].projectReference.name -ine $azdoProject) {
                Write-Host "Skipping service connection '$($PSStyle.Bold)$($serviceConnection.name)$($PSStyle.BoldOff)' because it is shared from project $($PSStyle.Bold)$($serviceConnection.serviceEndpointProjectReferences[0].projectReference.name)$($PSStyle.BoldOff) : ${originalServiceEndpointUrl}"
                continue
            }
            Write-Host "Service connection '$($serviceConnection.name)' is shared with the following projects:"
            $serviceConnection.serviceEndpointProjectReferences | ForEach-Object {
                "Service connection $($PSStyle.Bold){2}$($PSStyle.BoldOff) in project $($PSStyle.Bold){1}$($PSStyle.BoldOff) ({0}/{1}/_settings/adminservices?resourceId={3})" -f $OrganizationUrl, $_.projectReference.name, $_.name, $serviceConnection.id | Write-Host
            }
        }

        # Get application
        Write-Verbose "Getting application '$($serviceConnection.authorization.parameters.serviceprincipalid)' for service connection '$($serviceConnection.name)'..."
        $application = $null
        az ad app list --app-id $serviceConnection.authorization.parameters.serviceprincipalid `
                    --query "[0]" `
                    -o json `
                    | ConvertFrom-Json `
                    | Set-Variable -Name application
        if (!$application) {
            Write-Host "Application for service connection '$($PSStyle.Bold)$($serviceConnection.name)$($PSStyle.BoldOff)' not found, the service connection is using a Managed Identity or may be orphaned"
            continue
        }
        $application | Format-List | Out-String | Write-Debug
        Write-Verbose "Application displayName: $($application.displayName)"

        # Determine default and new application names
        "{0}-{1}-{2}" -f $organizationName, $azdoProject, $serviceConnection.data.subscriptionId `
                    | Set-Variable -Name defaultApplicationName
        Write-Verbose "Default application name: ${defaultApplicationName}"
        if ($Reset) {
            $newApplicationName = $defaultApplicationName
        } else {
            "{0}-{1}-{2}" -f $organizationName, $azdoProject, $serviceConnection.name `
                        | Set-Variable -Name newApplicationName
        }
        Write-Verbose "New application name: ${newApplicationName}"

        # Determine whether app has been renamed
        $serviceConnection | Add-Member "oldApplicationName" $application.displayName
        if ($application.displayName -eq $newApplicationName) {
            Write-Host "Application for service connection '$($PSStyle.Bold)$($serviceConnection.name)$($PSStyle.BoldOff)' has already been renamed to '$($PSStyle.Bold)${newApplicationName}$($PSStyle.BoldOff)'"
            continue
        }

        # Rename app
        $serviceConnection | Add-Member "newApplicationName" $newApplicationName
        Write-Host "Renaming application $($PSStyle.Bold)$($application.displayName)$($PSStyle.BoldOff) to '$($PSStyle.Bold)${newApplicationName}$($PSStyle.BoldOff)'..." -Nonewline
        if ($WhatIf) {
            Write-Host " skipped (WhatIf specified)"
            continue
        } else {
            Write-Host ""
        }
        az ad app update --id $application.appId `
                        --display-name $newApplicationName
    }

    # List processed service connection identities
    "`nService connections processed referencing an AAD application in {0}/{1}/_settings/adminservices created by {2}:" -f $OrganizationUrl, [uri]::EscapeDataString($azdoProject), $userName | Write-Host
    $serviceConnections | Format-Table -AutoSize -Property Name, @{Name="clientId";Expression={$_.authorization.parameters.serviceprincipalid}}, oldApplicationName, newApplicationName
}
