#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    List identities with old Azure DevOps issuer
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID ?? [guid]::Empty),

    [parameter(Mandatory=$false,HelpMessage="Issuer url")]
    [string]
    $Issuer="https://app.vstoken.visualstudio.com",

    [ValidateSet("Application", "ManagedIdentity")]
    [parameter(Mandatory=$false)]
    [string]
    $Type="Application"
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

Find-ApplicationsByIssuer -StartsWith $Issuer -Type $type | Set-Variable apps

Write-Host "Found $($apps.Count) Applications with Federation Subject '$Issuer'"
$apps | Format-Table -Property name, appId, federatedSubjects, issuers
