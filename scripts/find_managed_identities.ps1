#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Find a Managed Identities
.DESCRIPTION 
    Find a Managed Identities using Microsoft Graph API
.EXAMPLE
    ./find_managed_identities.ps1 mmyalias
.EXAMPLE
    ./find_managed_identities.ps1 -Search term -ManagedIdentityType UserCreated
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)]
    [ValidateNotNull()]
    [string]$Search,

    [parameter(Mandatory=$false)]
    [ValidateSet("UserCreated", "SystemCreated", "Any")]
    [string]$ManagedIdentityType="Any",

    [parameter(Mandatory=$false,HelpMessage="Azure Active Directory tenant ID")]
    [ValidateNotNull()]
    [guid]
    $TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) 

function Find-ManagedIdentityByNameMicrosoftGraph (
    [parameter(Mandatory=$true)][string]$StartsWith
) {
    if ($ManagedIdentityType -eq "UserCreated") {
        $jmesPathQuery = "?contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } elseif ($ManagedIdentityType -eq "SystemCreated") {
        $jmesPathQuery = "?!contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } else {
        $jmesPathQuery = ""
    }

    Write-Debug "az rest --method get --url `"https://graph.microsoft.com/v1.0/servicePrincipals?```$count=true&```$filter=startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'&```$select=appId,displayName,alternativeNames&```$orderBy=displayName`" --headers ConsistencyLevel=eventual --query `"value[${jmesPathQuery}] | [].{name:displayName,appId:appId,resourceId:alternativeNames[1]}`""
    az rest --method get `
            --url "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'&`$select=appId,displayName,alternativeNames&`$orderBy=displayName" `
            --headers ConsistencyLevel=eventual `
            --query "value[${jmesPathQuery}] | [].{name:displayName,appId:appId,resourceId:alternativeNames[1]}" `
            -o json `
            | ConvertFrom-Json `
            | Select-Object -Property name,appId,resourceId
}

function Find-ManagedIdentityByNameAzureResourceGraph (
    [parameter(Mandatory=$true)][string]$Search
) {
    if (!(az extension list --query "[?name=='resource-graph'].version" -o tsv)) {
        Write-Host "Adding Azure CLI extension 'resource-graph'..."
        az extension add -n resource-graph -y
    }
    
    $userAssignedGraphQuery = "Resources | where type =~ 'Microsoft.ManagedIdentity/userAssignedIdentities' and name contains '${Search}' | extend sp = parse_json(properties) | project name=name,appId=sp.clientId,resourceId=id | order by name asc"
    $systemGraphQuery = "Resources | where name contains '${Search}' | where isnotempty(parse_json(identity).principalId) | project name=name,appId='',resourceId=id | order by name asc"
    if ($ManagedIdentityType -eq "UserCreated") {
        $resourceGraphQuery = $userAssignedGraphQuery
    } elseif ($ManagedIdentityType -eq "SystemCreated") {
        $resourceGraphQuery = $systemGraphQuery
    } else {
        $resourceGraphQuery = "${userAssignedGraphQuery} | union (${systemGraphQuery}) | order by name asc"
    }
    Write-Debug "az graph query -q `"${resourceGraphQuery}`" -a --query `"data`""
    az graph query -q $resourceGraphQuery `
                   -a `
                   --query "data" `
                   -o json `
                   | ConvertFrom-Json `
                   | Select-Object -Property name,appId,resourceId
}

Write-Debug $MyInvocation.line
. (Join-Path $PSScriptRoot functions.ps1)

# Login to Azure CLI
Write-Verbose "Logging into Azure..."
Login-Az -Tenant ([ref]$TenantId)

if (!$Search) {
    # Take users alias as search term
    (az account show --query "user.name" -o tsv) -split '@' | Select-Object -First 1 | Set-Variable Search
    if (!$Search) {
        Write-Warning "Search term not provided, exiting"
        exit 1
    }
}
Write-Host "Searching for Managed Identities of type '${ManagedIdentityType}' matching '${Search}'..."

Write-Verbose "Microsoft Graph API results starting with '${Search}':"
Find-ManagedIdentityByNameMicrosoftGraph -StartsWith $Search | Set-Variable msftGraphObjects
$msftGraphObjects | Format-Table -AutoSize | Out-String | Write-Verbose

Write-Verbose "Azure Resource Graph results matching '${Search}':"
Find-ManagedIdentityByNameAzureResourceGraph -Search $Search | Set-Variable armResources
$armResources | Format-Table -AutoSize | Out-String | Write-Verbose

[system.collections.arraylist]$allObjects = @()
if ($msftGraphObjects -is [array]) {
    $allObjects = $msftGraphObjects
} else {
    $allObjects = @($msftGraphObjects)
}
if ($armResources -is [array]) {
    $allObjects.AddRange($armResources)
} else {
    $allObjects.Add($armResources) | Out-Null
}
Write-Host "User-created Managed Identities matching search term '${Search}':"
$allObjects | Sort-Object -Property name -Unique | Format-Table -AutoSize
