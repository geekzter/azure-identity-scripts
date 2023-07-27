#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find Azure DevOps Service Connections
.DESCRIPTION 
    Use the Microsoft Graph API to find Azure DevOps Service Connections by organization & project, using Azure DevOps Service Connection naming convention
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false,ParameterSetName="Organization",HelpMessage="Name of the Azure DevOps Organization")]
    [string]
    $Organization=(($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI) -split '/' | Select-Object -Skip 3),

    [parameter(Mandatory=$false,ParameterSetName="Organization",HelpMessage="Name of the Azure DevOps Project")]
    [string]
    $Project,

    [parameter(Mandatory=$false)]
    [switch]
    $HasCertificates=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasNoCertificates=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasFederation=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasNoFederation=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasSecrets=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasNoSecrets=$false,

    [parameter(Mandatory=$false,HelpMessage="Azure subscription id")]
    [ValidateNotNullOrEmpty()]
    [guid]
    $SubscriptionId,

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

$message = "Identities of type 'Application' in Azure DevOps"
if ($Organization) {
    $federationPrefix += "sc://${Organization}/"
    $namePrefix = "${Organization}-"
    $message += " organization '${Organization}'"
} elseif (!$HasFederation) {
    Write-Warning "Organization not specified, listing all Service Connections with federation instead"
    $HasFederation = $true
}
if ($Project) {
    if (!$Organization) {
        Write-Warning "Project '${Project}' requires Organization to be specified"
        exit 1
    }
    $federationPrefix += "${Project}/"
    $namePrefix += "${Project}-"
    $message += " and project '${Project}'"
}
$federationPrefix ??= "sc://"

if ($HasFederation) {
    $message += " using federation"
    Write-Host "Searching for ${message}..."
    Find-ApplicationsByFederation -StartsWith $federationPrefix | Set-Variable msftGraphObjects
} else {
    Write-Host "Searching for ${message}..."
    Find-ApplicationsByName -StartsWith $namePrefix | Set-Variable msftGraphObjects
}

Write-Host "${message}:"
$msftGraphObjects | Where-Object { 
    # We already check federation on organization/project, so we can ignore it here
    !$HasFederation -or $_.name -match "${Organization}-[^-]+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
} | Where-Object { 
    !$SubscriptionId -or $_.name -match $SubscriptionId
} | Where-Object { 
    $_.certCount -ge ($HasCertificates ? 1 : 0)
} | Where-Object { 
    !$HasNoCertificates -or $_.certCount -eq 0
} | Where-Object { 
    !$HasFederation -or $_.federatedSubjects -match "sc://[^/]+/[^/]+/[^/]+"
} | Where-Object { 
    !$HasNoFederation -or [string]::IsNullOrEmpty($_.federatedSubjects)
} | Where-Object { 
    $_.secretCount -ge ($HasSecrets ? 1 : 0)
} | Where-Object { 
    !$HasNoSecrets -or $_.secretCount -eq 0
} | Format-Table -AutoSize