#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Purge service connections referencing service principals that no longer exist
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

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID ?? [guid]::Empty)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)


# Get owned service connections using AAD tenant
$organizationName=($OrganizationUrl -split '/' | Select-Object -Index 3)
$OrganizationUrl -replace "/*$", "" | Set-Variable -Name OrganizationUrl
$userName=(az account show --query user.name -o tsv)
az devops service-endpoint list --project $Project `
                                --organization $OrganizationUrl `
                                --query "[?authorization.parameters.serviceprincipalid!=null && authorization.parameters.tenantid=='${TenantId}' && createdBy.uniqueName=='${userName}']" `
                                -o json `
                                | ConvertFrom-Json `
                                | Set-Variable -Name serviceConnections

$serviceConnections | Format-Table -AutoSize -Property Name | Out-String | Write-Debug

# Iterate through service connections
$projectUrl = ("{0}/{1}" -f $OrganizationUrl, [uri]::EscapeDataString($Project))
"Processing service connections referencing a service principal in {0}/_settings/adminservices created by {1}..." -f $projectUrl, $userName | Write-Host
foreach ($serviceConnection in $serviceConnections) {
    # Get service principal
    Write-Verbose "Getting service principal '$($serviceConnection.authorization.parameters.serviceprincipalid)' for service connection '$($serviceConnection.name)'..."
    $sp = $null
    az ad sp list --filter "appId eq '$($serviceConnection.authorization.parameters.serviceprincipalid)'" `
                  --query "[0]" `
                  -o json `
                  | ConvertFrom-Json `
                  | Set-Variable -Name sp
    if ($sp) {
        $sp | Format-List | Out-String | Write-Debug
        continue
    }
    Write-Host "Service Principal for service connection '$($serviceConnection.name)' not found, the service connection is orphaned"

    if (!$Force) {
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new("&Skip", "Leave service connection '$($serviceConnection.name)' as is")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Delete", "Delete service connection '$($serviceConnection.name)'")
        )
        $defaultChoice = 0
        $decision = $Host.UI.PromptForChoice("Continue", "Do you wish to proceed deleting service connection '$($serviceConnection.name)' from ${projectUrl}?", $choices, $defaultChoice)
    
        if ($decision -eq 0) {
            Write-Verbose "$($choices[$decision].HelpMessage)"
            continue
        } else {
            Write-Verbose "$($PSStyle.Formatting.Warning)$($choices[$decision].HelpMessage)$($PSStyle.Reset)"
        }

        Write-Host "Deleting service connection '$($serviceConnection.name)'..."
        az devops service-endpoint delete --id $($serviceConnection.id) --yes

    }    
}
