#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Convert a single or multiple Azure Resource Manager service connection(s) to use Workload identity federation

.DESCRIPTION 
    This script converts a single or multiple Azure Resource Manager service connection(s) to use Workload identity federation instead of a App Registration secret.
    The user will be prompted to confirm the conversion of each service connection. 
    The script will skip service connections that are shared from another project, were not created automatically, are not using an App Registration, or in a failed state.

    The user will be authenticated using the Azure CLI, which should be installed.

.LINK
    https://aka.ms/azdo-rm-workload-identity-conversion

.EXAMPLE
    ./convert_azurerm_service_connection_to_oidc.ps1 -Project <project> -ServiceConnectionId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    ./convert_azurerm_service_connection_to_oidc.ps1 -Project <project> -ServiceConnectionName <service connection name>

.EXAMPLE
    ./convert_azurerm_service_connection_to_oidc.ps1 -Project <project>

.EXAMPLE
    ./convert_azurerm_service_connection_to_oidc.ps1 -Project <project> -ErrorAction Stop -Verbose -Debug
#> 
#Requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'name')]
param ( 
    [parameter(Mandatory=$false,ParameterSetName="id",HelpMessage="Id of the Service Connection")]
    [guid]
    $ServiceConnectionId,

    [parameter(Mandatory=$false,ParameterSetName="name",HelpMessage="Name of the Service Connection")]
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
    $WhatIf=$false,

    [parameter(Mandatory=$false,HelpMessage="Don't show prompts")]
    [switch]
    $Force=$false
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)
$apiVersion = "7.1"

#-----------------------------------------------------------
# Log in to Azure
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. You can get it here: http://aka.ms/azure-cli"
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
az devops project show --project "${Project}" --organization $OrganizationUrl --query id -o tsv | Set-Variable projectId
if (!$projectId) {
    Write-Error "Project '${Project}' not found in organization '${OrganizationUrl}"
    exit 1
}

#-----------------------------------------------------------
# Retrieve the service connection

$baseEndpointUrl = "${OrganizationUrl}/${projectId}/_apis/serviceendpoint/endpoints"
if ($ServiceConnectionId) {
    $getApiUrl = "${baseEndpointUrl}/${ServiceConnectionId}?includeDetails=true&api-version=${apiVersion}"
} elseif ($ServiceConnectionName) {
    $getApiUrl = "${baseEndpointUrl}?endpointNames=${ServiceConnectionName}&type=azurerm&includeFailed=false&includeDetails=true&api-version=${apiVersion}"
} else {
    $getApiUrl = "${baseEndpointUrl}?authSchemes=ServicePrincipal&type=azurerm&includeFailed=false&includeDetails=true&api-version=${apiVersion}"
}
Write-Debug "GET $getApiUrl"
Invoke-RestMethod -Uri $getApiUrl `
                  -Method GET `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  -StatusCodeVariable httpStatusCode `
                  | Set-Variable serviceEndpointResponse
if ($ServiceConnectionId) {
    $serviceEndpoints = @($serviceEndpointResponse)
} else {
    $serviceEndpointResponse | Select-Object -ExpandProperty value `
                             | Set-Variable serviceEndpoints
}

Write-Debug "HTTP Status: ${httpStatusCode}"
if (!$httpStatusCode -or ($httpStatusCode -ge 300)) {
    Write-Error "Failed to convert service connection '$($serviceEndpoint.name)'"
    exit 1
}
$serviceEndpointResponse | ConvertTo-Json -Depth 5 | Write-Debug
$serviceEndpoints | Format-List | Out-String | Write-Debug
if (!$serviceEndpoints -or ($serviceEndpointResponse.count -eq 0)) {
    Write-Warning "No service connections found"
    exit 1
}

foreach ($serviceEndpoint in $serviceEndpoints) {
    "{0}/{1}/_settings/adminservices?resourceId={2}" -f $OrganizationUrl, $Project, $serviceEndpoint.id | Set-Variable serviceEndpointUrl
    Write-Verbose "Validating service connection '$($serviceEndpoint.name)' ($($serviceEndpointUrl))..."
    if ($serviceEndpoint.authorization.scheme -ine "ServicePrincipal") {
        Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because it does not use an App Registration (scheme is $($serviceEndpoint.authorization.scheme))"
        continue
    }
    if ($serviceEndpoint.data.creationMode -ine "Automatic") {
        Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because its App Registration was not created automatically"
        continue
    }
    "{0}/{1}/_settings/adminservices?resourceId={2}" -f $OrganizationUrl, $serviceEndpoint.serviceEndpointProjectReferences[0].projectReference.name, $serviceEndpoint.id | Set-Variable originalServiceEndpointUrl
    if ($serviceEndpoint.isShared) {
        if ($serviceEndpoint.serviceEndpointProjectReferences[0].projectReference.name -ine $Project) {
            Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because it is shared from another project: ${originalServiceEndpointUrl}"
            continue    
        }
        Write-Host "Service connection '$($serviceEndpoint.name)' is shared with the following projects:"
        $serviceEndpoint.serviceEndpointProjectReferences | ForEach-Object {
            "Service connection $($PSStyle.Bold){2}$($PSStyle.BoldOff) in project $($PSStyle.Bold){1}$($PSStyle.BoldOff) ({0}/{1}/_settings/adminservices?resourceId={3})" -f $OrganizationUrl, $_.projectReference.name, $_.name, $serviceEndpoint.id | Write-Host
        }
    }

    # Prompt user to confirm conversion (subscription name, spn name, etc.)
    if (!$Force) {
        # Prompt to continue
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new("&Convert", "Converting service connection '$($serviceEndpoint.name)'...")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Skip", "Skipping service connection '$($serviceEndpoint.name)'...")
            [System.Management.Automation.Host.ChoiceDescription]::new("&Exit", "Exit script")
        )
        $defaultChoice = $serviceEndpoint.isShared ? 1 : 0
        $prompt = $serviceEndpoint.isShared ? "Convert shared service connection '$($serviceEndpoint.name)'?" : "Convert service connection '$($serviceEndpoint.name)'?"
        $decision = $Host.UI.PromptForChoice([string]::Empty, $prompt, $choices, $defaultChoice)
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

    # Prepare request body
    $serviceEndpoint.authorization.scheme = "WorkloadIdentityFederation"
    $serviceEndpoint.data.PSObject.Properties.Remove('revertSchemeDeadline')
    $serviceEndpoint | ConvertTo-Json -Depth 4 | Set-Variable serviceEndpointRequest
    $putApiUrl = "${OrganizationUrl}/${projectId}/_apis/serviceendpoint/endpoints/$($serviceEndpoint.id)?operation=ConvertAuthenticationScheme&api-version=${apiVersion}"
    Write-Debug "PUT $putApiUrl"
    $httpStatusCode = $null

    # Convert service connection
    if ($WhatIf) {
        Write-Host "WhatIf: Convert service connection '$($serviceEndpoint.name)'"
        continue
    }
    try {
        Invoke-RestMethod -Uri $putApiUrl `
                          -Method PUT `
                          -Body $serviceEndpointRequest `
                          -ContentType 'application/json' `
                          -Authentication Bearer `
                          -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                          -StatusCodeVariable httpStatusCode `
                          | Set-Variable serviceEndpoint
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $_.Exception | Format-List | Out-String | Write-Debug
        $_.ErrorDetails | Format-List | Out-String | Write-Debug
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::BadRequest) {
            if ($serviceEndpoint.isShared) {
                # In case prior validation did not identity the original service endpoint
                Write-Warning "Skipping service connection '$($serviceEndpoint.name)' because it is shared from another project"
                continue
            }
            $_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -ExpandProperty message | Set-Variable errorMessage
        }
        "Failed to convert service connection {0} ({1}).`nService Endpoint REST API {2} returned {3}`n{4}" -f $serviceEndpoint.name, $serviceEndpointUrl, $putApiUrl, $_.Exception.Response.StatusCode, $errorMessage | Write-Warning
        throw $_
        exit 1
    } catch {
        $_.Exception | Format-List | Out-String | Write-Debug
        $_.ErrorDetails | Format-List | Out-String | Write-Debug
        "Failed to convert service connection {0} ({1}).`nREST API {2}`n{3}`n{4}" -f $serviceEndpoint.name, $serviceEndpointUrl, $putApiUrl, $_.Exception.Message, $_.ErrorDetails.Message | Write-Warning
        throw $_
        exit 1
    }

    Write-Debug "HTTP Status: ${httpStatusCode}"
    if (!$httpStatusCode -or ($httpStatusCode -ge 300)) {
        Write-Error "Failed to convert service connection '$($serviceEndpoint.name)'"
        exit 1
    }
    $serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
    if (!$serviceEndpoint) {
        Write-Error "Failed to convert service connection '$($serviceEndpoint.name)'"
        exit 1
    }
    Write-Host "Successfully converted service connection '$($serviceEndpoint.name)'"
}