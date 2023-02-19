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
    [ValidateNotNull()]
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
    $HasFederation=$false,

    [parameter(Mandatory=$false)]
    [switch]
    $HasSecrets=$false,

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
if ($Project) {
    $prefix += "${Project}-"
}

Write-Host "Searching for Identities of type '${IdentityType}' with prefix '${prefix}'..."
# Find-IdentitiesByNameMicrosoftGraph -StartsWith $prefix -IdentityType $IdentityType | Set-Variable msftGraphObjects
Find-ApplicationsByName -StartsWith $prefix | Set-Variable msftGraphObjects

$msftGraphObjects | Where-Object { 
    # Filter out objects not using a GUID as suffix
    $_.name -match "${Organization}-\w+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
} | Set-Variable msftGraphObjects -Scope global
if ($HasCertificates) {
    $msftGraphObjects | Where-Object {$_.keyCredentials -gt 0} | Set-Variable msftGraphObjects
}
if ($HasFederation) {
    $msftGraphObjects | Where-Object {![string]::IsNullOrEmpty($_.federationSubjects)} | Set-Variable msftGraphObjects
}
if ($HasSecrets) {
    $msftGraphObjects | Where-Object {$_.passwordCredentials -gt 0} | Set-Variable msftGraphObjects
}


Write-Host "Identities of type '${IdentityType}' with prefix '${prefix}':"
# $msftGraphObjects | Sort-Object -Property name -Unique | Format-Table -AutoSize
$msftGraphObjects | Format-Table -AutoSize