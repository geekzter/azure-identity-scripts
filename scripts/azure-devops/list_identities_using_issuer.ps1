#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    List identities with old Azure DevOps issuer
.EXAMPLE
    ./list_identities_using_issuer.ps1 -Issuer https://app.vstoken.visualstudio.com -Type Application
.EXAMPLE
    ./list_identities_using_issuer.ps1 -Issuer https://vstoken.dev.azure.com -Type ManagedIdentity
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID ?? [guid]::Empty),

    [parameter(Mandatory=$false,HelpMessage="Issuer url")]
    [string]
    $Issuer,

    [ValidateSet("Application", "ManagedIdentity")]
    [parameter(Mandatory=$false)]
    [string]
    $Type="Application"
) 

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot .. functions.ps1)

if (!$Issuer) {
    Invoke-Restmethod https://vstoken.dev.azure.com/.well-known/openid-configuration | Select-Object -ExpandProperty issuer `
                                                                                     | Set-Variable Issuer
}

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

Find-ApplicationsByIssuer -StartsWith $Issuer -Type $type | Set-Variable apps

Write-Host "`nFound $($apps.Count) identities of type '${Type}' with issuer '${Issuer}'"
$apps | Format-Table -Property name, appId, federatedSubjects, issuers
