#!/usr/bin/env pwsh
<# 
.SYNOPSIS 

.DESCRIPTION 

.LINK
    https://aka.ms/azdo-rm-workload-identity-conversion

.EXAMPLE

#> 
#Requires -Version 7.2

param ( 
    [parameter(Mandatory=$false,HelpMessage="Name of the Service Connection")]
    [string]
    $ServiceConnectionName,

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    [ValidateNotNullOrEmpty()]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI),

    [parameter(Mandatory=$false,HelpMessage="Don't show prompts")]
    [switch]
    $Force=$false
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)
$apiVersion = "7.1-preview.4"

#-----------------------------------------------------------
# Log in to Azure
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. You can get it here: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}
az account show -o json 2>$null | ConvertFrom-Json | Set-Variable account
if (!$account) {
    az login --allow-no-subscriptions -o json | ConvertFrom-Json | Set-Variable account
}
# Log in to Azure & Azure DevOps
$OrganizationUrl = $OrganizationUrl.ToString().Trim('/')
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 `
                            --query "accessToken" `
                            --output tsv `
                            | Set-Variable accessToken
if (!$accessToken) {
    Write-Error "$(account.user.name) failed to get access token for Azure DevOps"
    exit 1
}
if (!(az extension list --query "[?name=='azure-devops'].version" -o tsv)) {
    Write-Host "Adding Azure CLI extension 'azure-devops'..."
    az extension add -n azure-devops -y -o none
}
$accessToken | az devops login --organization $OrganizationUrl
if ($lastexitcode -ne 0) {
    Write-Error "$($account.user.name) failed to log in to Azure DevOps organization '${OrganizationUrl}'"
    exit $lastexitcode
}

#-----------------------------------------------------------
# Check parameters
az devops project show --project $Project --organization $OrganizationUrl --query id -o tsv | Set-Variable projectId
if (!$projectId) {
    Write-Error "Project '${Project}' not found in organization '${OrganizationUrl}"
    exit 1
}

#-----------------------------------------------------------
# Retrieve the service connection
$getApiUrl = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints?type=azurerm&includeFailed=false&includeDetails=true&api-version=${apiVersion}"
if ($ServiceConnectionName) {
    $getApiUrl += "&endpointNames=${ServiceConnectionName}"
} else {
    $getApiUrl += "&authSchemes=ServicePrincipal"
}
Write-Debug "GET $getApiUrl"
Invoke-RestMethod -Uri $getApiUrl `
                  -Method GET `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  | Tee-Object -Variable serviceEndpointResponse `
                  | Select-Object -ExpandProperty value `
                  | Set-Variable serviceEndpoints
$serviceEndpoints | Format-List | Out-String | Write-Debug
if (!$serviceEndpoints -or ($serviceEndpointResponse.count-eq 0)) {
    Write-Warning "No service connections found"
    exit 1
}

foreach ($serviceEndpoint in $serviceEndpoints) {
    if ($serviceEndpoint.authorization.scheme -ine "ServicePrincipal") {
        Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because it does not use an App Registration (scheme is $($serviceEndpoint.authorization.scheme))"
        continue
    }
    if ($serviceEndpoint.data.creationMode -ine "Automatic") {
        Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because its App Registration was not created automatically"
        continue
    }
    if ($serviceEndpoint.isShared) {
        Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because it is shared with with (an)other project(s)"
        continue
    }

    $serviceEndpoint.authorization.scheme = "WorkloadIdentityFederation"
    $serviceEndpoint | ConvertTo-Json -Depth 4 | Set-Variable serviceEndpointRequest

    # Prompt user to confirm conversion (subscription name, spn name, etc.)
    if (!$Force) {
        # Prompt to continue
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new("&Convert", "Converting service connection '$($serviceEndpoint.name)'...")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Skip", "Skipping service connection '$($serviceEndpoint.name)'...")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Exit", "Exit script")
        )
        $defaultChoice = 1
        $decision = $Host.UI.PromptForChoice([string]::Empty, "Convert service connection '$($serviceEndpoint.name)'?", $choices, $defaultChoice)
        Write-Debug "Decision: $decision"

        if ($decision -eq 0) {
            Write-Host "$($choices[$decision].HelpMessage)"
        } elseif ($decision -eq 1) {
            Write-Host "$($PSStyle.Formatting.Warning)$($choices[$decision].HelpMessage)$($PSStyle.Reset)"
            continue 
        } elseif ($decision -ge 2) {
            Write-Host "$($PSStyle.Formatting.Warning)$($choices[$decision].HelpMessage)$($PSStyle.Reset)"
            exit 
        }
    }

    $putApiUrl = "${OrganizationUrl}/${Project}/_apis/serviceendpoint/endpoints/$($serviceEndpoint.id)?operation=ConvertAuthenticationScheme&api-version=${apiVersion}"
    Write-Debug "GET $putApiUrl"
    Invoke-RestMethod -Uri $putApiUrl `
                      -Method PUT`
                      -Body $serviceEndpointRequest `
                      -ContentType 'application/json' `
                      -Authentication Bearer `
                      -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                      | Set-Variable serviceEndpoint

    $serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
    if (!$serviceEndpoint) {
        Write-Error "Failed to convert service connection '$($serviceEndpoint.name)'"
        exit 1
    }
    Write-Host "Successfully converted service connection '$($serviceEndpoint.name)'"
}