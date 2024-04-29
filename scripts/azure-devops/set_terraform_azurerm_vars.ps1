#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Prepares Terraform azure provider environment variables
 
.EXAMPLE
    ./set_terraform_azurerm_vars.ps1

.EXAMPLE
./set_terraform_azurerm_vars.ps1 -RequestNewToken -SystemAccessToken $(System.AccessToken)
#> 
#Requires -Version 7.2
[CmdletBinding(DefaultParameterSetName="None")]
param ( 
    [Parameter(Mandatory=$false)]
    [Parameter(ParameterSetName="NewToken",Mandatory=$true)]
    [switch]
    $RequestNewToken=$false,

    [Parameter(Mandatory=$false)]
    [Parameter(ParameterSetName="NewToken",Mandatory=$true)]
    [string]
    $SystemAccessToken=$env:SYSTEM_ACCESSTOKEN
) 

if ($env:SYSTEM_DEBUG -eq "true") {
    $InformationPreference = "Continue"
    $VerbosePreference = "Continue"
    $DebugPreference = "Continue"
    
    Get-ChildItem -Path Env: -Force -Recurse -Include * -Exclude *TOKEN | Sort-Object -Property Name | Format-Table -AutoSize | Out-String
}

function New-OidcToken()
{
    Write-Verbose "`nRequesting OIDC token from Azure DevOps..."
    $oidcRequestUrl = "${env:SYSTEM_OIDCREQUESTURI}?api-version=7.1&serviceConnectionId=${env:AZURESUBSCRIPTION_SERVICE_CONNECTION_ID}"
    Invoke-RestMethod -Headers @{
                        Authorization  = "Bearer ${SystemAccessToken}"
                        'Content-Type' = 'application/json'
                      } `
                      -Uri "${oidcRequestUrl}" `
                      -Method Post `
                      | Set-Variable oidcTokenResponse
    $oidcToken = $oidcTokenResponse.oidcToken
    if (!$oidcToken) {
        throw "Could not get OIDC token from ${oidcRequestUrl}"
    }
    if ($oidcToken -notmatch "^ey") {
        throw "OIDC token from ${oidcRequestUrl} has unexpected format"
    }
    return $oidcToken
}


# Propagate Azure context to Terraform
az account show 2>$null | ConvertFrom-Json | Set-Variable account
if (!$account) {
    Write-Warning "Not logged into Azure CLI, no context to propagate as ARM_* environment variables"
}
if (![guid]::TryParse($account.user.name, [ref][guid]::Empty)) {
    Write-Warning "Azure CLI logged in with a User Principal instead of a Service Principal"
}

if ($RequestNewToken -and !$env:servicePrincipalKey) {
    $idToken = New-OidcToken    
} else {
    $idToken = $env:idToken # requires addSpnToEnvironment: true
}

$env:ARM_CLIENT_ID       ??= $account.user.name
$env:ARM_CLIENT_SECRET   ??= $env:servicePrincipalKey # requires addSpnToEnvironment: true
$env:ARM_OIDC_TOKEN        = $idToken
$env:ARM_SUBSCRIPTION_ID ??= $account.id  
$env:ARM_TENANT_ID       ??= $account.tenantId
$env:ARM_USE_CLI         ??= (!($idToken -or $env:servicePrincipalKey)).ToString().ToLower()
$env:ARM_USE_OIDC        ??= ($idToken -ne $null).ToString().ToLower()
if ($env:ARM_CLIENT_SECRET) {
    Write-Verbose "Using ARM_CLIENT_SECRET"
} elseif ($env:ARM_OIDC_TOKEN) {
    Write-Verbose "Using ARM_OIDC_TOKEN"
} else {
    Write-Warning "No credentials found to propagate as ARM_* environment variables. Using ARM_USE_CLI = true."
}
Write-Host "`nTerraform azure provider environment variables:" -NoNewline
Get-ChildItem -Path Env: -Recurse -Include ARM_* | ForEach-Object { 
                                                       if ($_.Name -match 'SECRET|TOKEN') {
                                                           $_.Value = '***'
                                                       } 
                                                       $_
                                                   } `
                                                 | Sort-Object -Property Name `
                                                 | Format-Table -HideTableHeader
