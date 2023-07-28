#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Create a Service Connection in Azure DevOps that uses a Managed Identity and Workload Identity federation to authenticate to Azure.

.DESCRIPTION 
    Creates a Managed Identiy, sets up a federation subject on the Managed Identity for a Service Connection, creates the Service Connection, and grants the Managed Identity the Contributor role on the subscription.

.LINK
    https://aka.ms/azdo-rm-workload-identity

.EXAMPLE
    ./create_azurerm_msi_oidc_service_connection.ps1 -Project MyProject -OrganizationUrl https://dev.azure.com/MyOrg -SubscriptionId 00000000-0000-0000-0000-000000000000
#> 
#Requires -Version 7.2

param ( 
    [parameter(Mandatory=$false,HelpMessage="Name of the Managed Identity")]
    [string]
    $IdentityName,

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure Resource Group where the Managed Identity will be created")]
    [string]
    $IdentityResourceGroupName,
    
    [parameter(Mandatory=$false,HelpMessage="Id of the Azure Subscription where the Managed Identity will be created")]
    [guid]
    $IdentitySubscriptionId=($env:AZURE_SUBSCRIPTION_ID || $env:ARM_SUBSCRIPTION_ID),

    [parameter(Mandatory=$false,HelpMessage="Azure region of the Managed Identity")]
    [string]
    $IdentityLocation,

    [parameter(Mandatory=$false,HelpMessage="Name of the Service Connection")]
    [string]
    $ServiceConnectionName,

    [parameter(Mandatory=$false,HelpMessage="Role to grant the Service Connection on the selected scope")]
    [string]
    [ValidateNotNullOrEmpty()]
    $ServiceConnectionRole="Contributor",

    [parameter(Mandatory=$false,HelpMessage="Scope of the Service Connection (e.g. /subscriptions/00000000-0000-0000-0000-000000000000)")]
    [string]
    [ValidatePattern("^$|(?i)/subscriptions/[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}(/resourcegroups/(.+?))?")]
    $ServiceConnectionScope,

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    [ValidateNotNullOrEmpty()]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL || $env:SYSTEM_COLLECTIONURI)
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)
$apiVersion = "7.1-preview.4"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. You can get it here: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

#-----------------------------------------------------------
# Log in to Azure
az account show -o json 2>$null | ConvertFrom-Json | Set-Variable subscription
if (!$subscription) {
    az login -o json | ConvertFrom-Json | Set-Variable subscription
}
$subscription | Format-List | Out-String | Write-Debug
if ($IdentitySubscriptionId) {
    az account set --subscription $IdentitySubscriptionId -o none
    az account show -o json 2>$null | ConvertFrom-Json | Set-Variable subscription
} else {
    # Prompt for subscription
    az account list --query "sort_by([].{id:id, name:name},&name)" `
                    -o json `
                    | ConvertFrom-Json `
                    | Set-Variable subscriptions

    if ($subscriptions.Length -eq 1) {
        $occurrence = 0
    } else {
        # Active subscription may not be the desired one, prompt the user to select one
        $index = 0
        $subscriptions | Format-Table -Property @{name="index";expression={$script:index;$script:index+=1}}, id, name
        Write-Host "Set `$env:ARM_SUBSCRIPTION_ID to the id of the subscription you want to use to prevent this prompt" -NoNewline

        do {
            Write-Host "`nEnter the index # of the subscription you want to use: " -ForegroundColor Cyan -NoNewline
            [int]$occurrence = Read-Host
            Write-Debug "User entered index '$occurrence'"
        } while (($occurrence -notmatch "^\d+$") -or ($occurrence -lt 1) -or ($occurrence -gt $subscriptions.Length))
    }

    $subscription = $subscriptions[$occurrence-1]
    $IdentitySubscriptionId = $subscription.id

    Write-Host "Using subscription '$($subscription.name)'" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 250
}

# Log in to Azure & Azure DevOps
$OrganizationUrl = $OrganizationUrl.ToString().Trim('/')
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 `
                            --query "accessToken" `
                            --output tsv `
                            | Set-Variable accessToken
if (!$accessToken) {
    Write-Error "$(subscription.user.name) failed to get access token for Azure DevOps"
    exit 1
}
if (!(az extension list --query "[?name=='azure-devops'].version" -o tsv)) {
    Write-Host "Adding Azure CLI extension 'azure-devops'..."
    az extension add -n azure-devops -y -o none
}
$accessToken | az devops login --organization $OrganizationUrl
if ($lastexitcode -ne 0) {
    Write-Error "$($subscription.user.name) failed to log in to Azure DevOps organization '${OrganizationUrl}'"
    exit
}

#-----------------------------------------------------------
# Process parameters, making sure they're not empty
$organizationName = $OrganizationUrl.ToString().Split('/')[3]
if (!$IdentityResourceGroupName) {
    $IdentityResourceGroupName = (az config get defaults.group --query value -o tsv)
}
if (!$IdentityResourceGroupName) {
    $IdentityResourceGroupName = "VS-${organizationName}-Group"
}
az group show -g $IdentityResourceGroupName -o json 2>$null | ConvertFrom-Json | Set-Variable resourceGroup
if ($resourceGroup) {
    if (!$IdentityLocation) {
        $IdentityLocation = $resourceGroup.location
    }
} else {
    if (!$IdentityLocation) {
        $IdentityLocation = (az config get defaults.location --query value -o tsv)
    }
    if (!$IdentityLocation) {
        # Azure location doesn't really matter for MI; the object is in AAD which is a global service
        $IdentityLocation = "southcentralus"
    }
    az group create -g $IdentityResourceGroupName -l $IdentityLocation -o json | ConvertFrom-Json | Set-Variable resourceGroup
}
if (!$ServiceConnectionScope) {
    $ServiceConnectionScope = "/subscriptions/${IdentitySubscriptionId}"
    Write-Verbose "Parameter ServiceConnectionScope not provided, using '${ServiceConnectionScope}'."
}
$serviceConnectionSubscriptionId = $ServiceConnectionScope.Split('/')[2]

#-----------------------------------------------------------
# Check whether project exists
az devops project show --project $Project --query id -o tsv | Set-Variable projectId
if (!$projectId) {
    Write-Error "Project '${Project}' not found in organization '${OrganizationUrl}"
    exit 1
}

# Test whether Service Connection already exists
$serviceConnectionSubscriptionName = $(az account show --subscription $serviceConnectionSubscriptionId --query name -o tsv)
if (!$ServiceConnectionName) {
    $ServiceConnectionName = $serviceConnectionSubscriptionName
    $serviceConnectionResourceGroupName = $ServiceConnectionScope.Split('/')[4]
    if ($serviceConnectionResourceGroupName) {
        $ServiceConnectionName += "-${serviceConnectionResourceGroupName}"
    }
    $ServiceConnectionName += "-oidc-msi"
}
do {
    az devops service-endpoint list -p $Project `
                                    --query "[?name=='${ServiceConnectionName}'].id" `
                                    -o tsv `
                                    | Set-Variable serviceEndpointId

    $ServiceConnectionNameBefore = $ServiceConnectionName
    if ($serviceEndpointId) {
        Write-Warning "Service connection '${ServiceConnectionName}' already exists. Provide a different name to create a new service connection or press enter to overwrite '${ServiceConnectionName}'."
        $ServiceConnectionName = Read-Host -Prompt "Provide the name of the service connection ('${ServiceConnectionName}')"
        if (!$ServiceConnectionName) {
            $ServiceConnectionName = $ServiceConnectionNameBefore
        }
        if ($ServiceConnectionName -ieq $ServiceConnectionNameBefore) {
            Write-Verbose "Service connection '${ServiceConnectionName}' (${serviceEndpointId}) wil be updated"
            break
        }
    } else {
        Write-Verbose "Service connection '${ServiceConnectionName}' (${serviceEndpointId}) wil be created"
    }
} while ($serviceEndpointId)

#-----------------------------------------------------------
# Create Managed Identity
if (!$IdentityName) {
    $IdentityName = "${organizationName}-${Project}-${ServiceConnectionName}"
}
Write-Verbose "Creating Managed Identity '${IdentityName}' in resource group '${IdentityResourceGroupName}'..."
Write-Debug "az identity create -n $IdentityName -g $IdentityResourceGroupName -l $IdentityLocation --subscription $IdentitySubscriptionId"
az identity create -n $IdentityName `
                   -g $IdentityResourceGroupName `
                   -l $IdentityLocation `
                   --subscription $IdentitySubscriptionId `
                   -o json `
                   | ConvertFrom-Json `
                   | Set-Variable identity
Write-Verbose "Created Managed Identity $($identity.id)"

$federatedSubject = "sc://${organizationName}/${Project}/${ServiceConnectionName}"
Write-Verbose "Configuring Managed Identity '${IdentityName}' with federated subject '${federatedSubject}'..."
az identity federated-credential create --name $IdentityName `
                                        --identity-name $IdentityName  `
                                        --resource-group $IdentityResourceGroupName `
                                        --issuer https://app.vstoken.visualstudio.com `
                                        --subject $federatedSubject `
                                        --subscription $IdentitySubscriptionId `
                                        -o json `
                                        | ConvertFrom-Json `
                                        | Set-Variable federatedCredential
Write-Verbose "Created federated credential $($federatedCredential.id)"
$identity | Add-Member -NotePropertyName federatedSubject -NotePropertyValue $federatedSubject
$identity | Add-Member -NotePropertyName role -NotePropertyValue $ServiceConnectionRole
$identity | Add-Member -NotePropertyName scope -NotePropertyValue $ServiceConnectionScope
$identity | Add-Member -NotePropertyName subscriptionId -NotePropertyValue $IdentitySubscriptionId
$identity | Format-List | Out-String | Write-Debug

Write-Verbose "Creating role assignment for Managed Identity '${IdentityName}' on subscription '$($subscription.name)'..."
az role assignment create --assignee-object-id $identity.principalId `
                          --assignee-principal-type ServicePrincipal `
                          --role $ServiceConnectionRole `
                          --scope $ServiceConnectionScope `
                          --subscription $serviceConnectionSubscriptionId `
                          -o json `
                          | ConvertFrom-Json `
                          | Set-Variable roleAssignment
Write-Verbose "Created role assignment $($roleAssignment.id)"

Write-Host "`nManaged Identity '$($identity.name)':"
$identity | Format-List -Property id, clientId, federatedSubject, role, scope, subscriptionId, tenantId

#-----------------------------------------------------------
# TODO: Create the service connection (Azure CLI)
# az devops service-endpoint azurerm create --azure-rm-service-principal-id $identity.clientId `
#                                           --azure-rm-subscription-id $serviceConnectionSubscriptionId `
#                                           --azure-rm-subscription-name $ServiceConnectionName `
#                                           --azure-rm-tenant-id $identity.tenantId `
#                                           --name $IdentityName `
#                                           --organization $OrganizationUrl `
#                                           --project $Project `
                                        
# Prepare service connection REST API request body
Write-Verbose "Creating / updating service connection '${ServiceConnectionName}'..."
Get-Content -Path (Join-Path $PSScriptRoot serviceEndpointRequest.json) `
            | ConvertFrom-Json `
            | Set-Variable serviceEndpointRequest

$serviceEndpointDescription = "Created by $($MyInvocation.MyCommand.Name). Configured Managed Identity ${IdentityName} (clientId $($identity.clientId)) federated on ${federatedSubject} as ${ServiceConnectionRole} on scope ${ServiceConnectionScope}."
$serviceEndpointRequest.authorization.parameters.servicePrincipalId = $identity.clientId
$serviceEndpointRequest.authorization.parameters.tenantId = $identity.tenantId
$serviceEndpointRequest.data.subscriptionId = $serviceConnectionSubscriptionId
$serviceEndpointRequest.data.subscriptionName = $serviceConnectionSubscriptionName
$serviceEndpointRequest.description = $serviceEndpointDescription
$serviceEndpointRequest.name = $ServiceConnectionName
$serviceEndpointRequest.serviceEndpointProjectReferences[0].description = $serviceEndpointDescription
$serviceEndpointRequest.serviceEndpointProjectReferences[0].name = $ServiceConnectionName
$serviceEndpointRequest.serviceEndpointProjectReferences[0].projectReference.id = $projectId
$serviceEndpointRequest.serviceEndpointProjectReferences[0].projectReference.name = $Project
$serviceEndpointRequest | ConvertTo-Json -Depth 4 | Set-Variable serviceEndpointRequestBody
Write-Debug "Service connection request body: `n${serviceEndpointRequestBody}"

$apiUri = "${OrganizationUrl}/_apis/serviceendpoint/endpoints"
if ($serviceEndpointId) {
    $apiUri += "/${serviceEndpointId}"
}
$apiUri += "?api-version=${apiVersion}"
Invoke-RestMethod -Uri $apiUri `
                  -Method ($serviceEndpointId ? 'PUT' : 'POST') `
                  -Body $serviceEndpointRequestBody `
                  -ContentType 'application/json' `
                  -Authentication Bearer `
                  -Token (ConvertTo-SecureString $accessToken -AsPlainText) `
                  | Set-Variable serviceEndpoint

$serviceEndpoint | ConvertTo-Json -Depth 4 | Write-Debug
if (!$serviceEndpoint) {
    Write-Error "Failed to create / update service connection '${ServiceConnectionName}'"
    exit 1
}

if ($serviceEndpointId) {
    Write-Host "Service connection '${ServiceConnectionName}' updated:"
} else {
    Write-Host "Service connection '${ServiceConnectionName}' created:"
}
$serviceEndpoint | Select-Object -Property authorization, data, id, name, description, type, createdBy `
                 | ForEach-Object { 
                 $_.createdBy = $_.createdBy.uniqueName
                 $_ | Add-Member -NotePropertyName clientId -NotePropertyValue $_.authorization.parameters.serviceprincipalid
                 $_ | Add-Member -NotePropertyName creationMode -NotePropertyValue $_.data.creationMode
                 $_ | Add-Member -NotePropertyName scheme -NotePropertyValue $_.authorization.scheme
                 $_ | Add-Member -NotePropertyName scopeLevel -NotePropertyValue $_.data.scopeLevel
                 $_ | Add-Member -NotePropertyName subscriptionName -NotePropertyValue $_.data.subscriptionName
                 $_ | Add-Member -NotePropertyName subscriptionId -NotePropertyValue $_.data.subscriptionId
                 $_ | Add-Member -NotePropertyName tenantid -NotePropertyValue $_.authorization.parameters.tenantid
                 $_ | Add-Member -NotePropertyName workloadIdentityFederationSubject -NotePropertyValue $_.authorization.parameters.workloadIdentityFederationSubject
                 $_
                 } `
                 | Select-Object -ExcludeProperty authorization, data
                 | Format-List
