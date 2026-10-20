#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Converts Workload identity service connections that use the Azure DevOps issuer to use the Entra issuer instead

.DESCRIPTION 
    Converts Workload identity service connections that use the Azure DevOps issuer to use the Entra issuer instead.
    This script requires Microsoft graph access only, enabling central teams to manage service connection conversion for a given Azure DevOps organization without needing direct access to individual service connections.

.LINK
    https://aka.ms/azdo-issuer

.EXAMPLE
    ./convert_azdo_issuer_service_connection.ps1 -OrganizationUrl https://dev.azure.com/foo -Project bar

    .EXAMPLE
    ./convert_azdo_issuer_service_connection.ps1 -OrganizationUrl https://dev.azure.com/foo -Project $null
#> 
#Requires -Version 7.2

param ( 
    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI),

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    $Project=$env:SYSTEM_TEAMPROJECT

) 

$organization = ($OrganizationUrl -split '/' | Select-Object -Index 3)
$subjectPrefix = "sc://${organization}/${Project}"
Write-Verbose "FIC subject prefix: $subjectPrefix"

# Gather application ids from Microsoft Graph with a matching federated credential subject
az rest --method get `
        --url "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=federatedIdentityCredentials&`$filter=signInAudience eq 'AzureADMyOrg' and federatedIdentityCredentials/any(f:startsWith(f/subject,'${subjectPrefix}'))&`$select=id,appId,displayName,federatedIdentityCredentials" `
        --headers ConsistencyLevel=eventual `
        --query "value[].{name:displayName,appId:appId,id:id,federatedSubjects:join(',',federatedIdentityCredentials[].subject),issuers:join(',',federatedIdentityCredentials[].issuer)}" `
        -o json `
        | Tee-Object -Variable azdoIssuerAppsJSON `
        | ConvertFrom-Json `
        | Set-Variable -Name azdoIssuerApps

Write-Debug "Retrieved Azure DevOps issuer applications JSON: $azdoIssuerAppsJSON"

foreach ($azdoIssuerApp in $azdoIssuerApps) {
    # Process each Azure DevOps issuer application here
    $azdoIssuerApp
    Write-Verbose "Processing Azure DevOps issuer application: $($azdoIssuerApp.name)"
    foreach ($federatedSubject in $azdoIssuerApp.federatedSubjects -split ',') {
        # Process each federated subject here
        if ($federatedSubject -match "^${subjectPrefix}") {
            # Prompt user to confirm conversion
            $choices = @(
                [System.Management.Automation.Host.ChoiceDescription]::new("&Convert", "Converting service connection with subject '${federatedSubject}'...")
                [System.Management.Automation.Host.ChoiceDescription]::new("&Skip", "Skipping service connection '${federatedSubject}'...")
                [System.Management.Automation.Host.ChoiceDescription]::new("&Exit", "Exit script")
            )
            $prompt = "Convert service connection with subject '${federatedSubject}'?"
            $defaultChoice = $serviceEndpoint.isShared ? 1 : 0
            if (!$WhatIf) {
                $decision = $Host.UI.PromptForChoice([string]::Empty, $prompt, $choices, $defaultChoice)
            } else {
                $decision = $defaultChoice
            }

            Write-Host "$($choices[$decision].HelpMessage)"
            if ($decision -eq 1) {
                continue 
            } elseif ($decision -ge 2) {
                exit 
            }

            Write-Host "Initiating conversion of service endpoint for federated subject: ${federatedSubject}"
            az devops service-endpoint convert --azdo-subject $federatedSubject
        }
    }
}