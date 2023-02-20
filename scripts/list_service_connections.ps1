#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find Azure DevOps Service Connections
.DESCRIPTION 
    Use the Microsoft Graph API to find Azure DevOps Service Connections by organisation & project, using Azure DevOps Service Connection naming convention
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false,ParameterSetName="Organization",HelpMessage="Name of the Azure DevOps Organization")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Organization=($env:AZDO_ORG_SERVICE_URL -split '/' | Select-Object -Skip 3),

    [parameter(Mandatory=$false,ParameterSetName="Organization",HelpMessage="Name of the Azure DevOps Project")]
    [ValidateNotNull()]
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

    # [parameter(Mandatory=$false)]
    # [ValidateSet("ServicePrincipal", "UserCreatedManagedIdentity", "Any")]
    # [string]
    # $IdentityType="Any",

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

$prefix = "${Organization}-"
$message = "Identities of type 'Application' in Azure DevOps organization '${Organization}'"
if ($Project) {
    $prefix += "${Project}-"
    $message += " and project '${Project}'"
}

Write-Host "Searching for ${message}..."
# Find-IdentitiesByNameMicrosoftGraph -StartsWith $prefix -IdentityType $IdentityType | Set-Variable msftGraphObjects
Find-ApplicationsByName -StartsWith $prefix | Set-Variable msftGraphObjects

Write-Host "${message}:"
$msftGraphObjects | Where-Object { 
    # Filter out objects not using a GUID as suffix
    $_.name -match "${Organization}-[^-]+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
} | Where-Object { 
    $_.keyCredentials -ge ($HasCertificates ? 1 : 0)
} | Where-Object { 
    !$HasNoCertificates -or $_.keyCredentials -eq 0
} | Where-Object { 
    !$HasFederation -or ![string]::IsNullOrEmpty($_.federatedIdentityCredentials)
} | Where-Object { 
    !$HasNoFederation -or [string]::IsNullOrEmpty($_.federatedIdentityCredentials)
} | Where-Object { 
    $_.passwordCredentials -ge ($HasSecrets ? 1 : 0)
} | Where-Object { 
    !$HasNoSecrets -or $_.passwordCredentials -eq 0
} | Sort-Object -Property name -Unique | Format-Table -AutoSize