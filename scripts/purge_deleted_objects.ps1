#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Purge deleted objects from Azure Active Directory
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)]
    [ValidateSet("Application", "Group")]
    [string]
    $ObjectType="Application",

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant id")]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

New-TemporaryFile | Select-Object -ExpandProperty FullName | Set-Variable jsonBodyFile
Write-Debug "jsonBodyFile: $jsonBodyFile"
@{
    "userId"     = $(az ad signed-in-user show --query id -o tsv)
    "type"       = $ObjectType
} | ConvertTo-Json | Set-Content -Path $jsonBodyFile
Get-Content -Path $jsonBodyFile | Write-Debug

az rest --method post `
        --url "https://graph.microsoft.com/v1.0/directory/deletedItems/getUserOwnedObjects" `
        --headers "Content-Type=application/json" `
        --body `@$jsonBodyFile `
        --query "value[]" `
        -o json `
        | ConvertFrom-Json `
        | Set-Variable deletedObjects
$deletedObjects | Format-List | Out-String | Write-Debug

if (!$deletedObjects) {
    Write-Host "No deleted objects found."
    exit
}

foreach ($deletedObject in $deletedObjects) {
    Write-Host "Deleting application: '$($deletedObject.displayName)'..."
    $deletedObjectId = $deletedObject.id
    Write-Debug "deletedObjectId: $deletedObjectId"
    az rest --method delete `
            --url "https://graph.microsoft.com/v1.0/directory/deletedItems/${deletedObjectId}" `
            | Write-Debug
}