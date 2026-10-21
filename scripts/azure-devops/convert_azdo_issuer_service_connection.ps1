#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Converts Workload identity service connections that use the Azure DevOps issuer to use the Entra issuer instead

.DESCRIPTION 
    Converts Workload identity service connections that use the Azure DevOps issuer to use the Entra issuer instead.
    This script requires Microsoft graph access only, enabling central teams to manage service connection conversion for a given Azure DevOps organization without needing direct access to individual service connections.
    Follows Microsoft Graph pagination links, prompting for conversion of matching applications on each page.

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
if ($Project) {
    $subjectPrefix = "sc://${organization}/${Project}/"
} else {
    $subjectPrefix = "sc://${organization}/"
}
Write-Verbose "FIC subject prefix: $subjectPrefix"

# Gather application ids from Microsoft Graph with a matching federated credential subject
$graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=federatedIdentityCredentials&`$filter=signInAudience eq 'AzureADMyOrg' and federatedIdentityCredentials/any(f:startsWith(f/subject,'${subjectPrefix}'))&`$select=id,appId,displayName,federatedIdentityCredentials"
do {
    $azdoIssuerAppsJSON = az rest --method get `
                                  --url $graphUrl `
                                  --headers ConsistencyLevel=eventual `
                                  -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve Azure DevOps issuer applications from Microsoft Graph (exit code $LASTEXITCODE)."
    }

    Write-Debug "Retrieved Azure DevOps issuer applications JSON: $azdoIssuerAppsJSON"
    $page = $azdoIssuerAppsJSON | ConvertFrom-Json -ErrorAction Stop
    foreach ($application in $page.value) {
        $azdoIssuerApp = [PSCustomObject]@{
            name = $application.displayName
            appId = $application.appId
            id = $application.id
            federatedSubjects = $application.federatedIdentityCredentials.subject -join ','
            issuers = $application.federatedIdentityCredentials.issuer -join ','
        }
        # Process each Azure DevOps issuer application here
        Write-Verbose "Processing Azure DevOps issuer application: $($azdoIssuerApp.name)"
        $azdoIssuerApp
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
                # $decision = $Host.UI.PromptForChoice([string]::Empty, $prompt, $choices, 0)
                continue

                Write-Host "$($choices[$decision].HelpMessage)"
                if ($decision -eq 1) {
                    continue 
                } elseif ($decision -ge 2) {
                    exit 
                }

                Write-Host "Initiating conversion of service endpoint for federated subject: ${federatedSubject}"
                # This requires the user to have Microsoft Graph permissions to convert the service endpoint. No Azure DevOps permissions are needed.
                az devops service-endpoint convert --azdo-subject $federatedSubject
            }
        }
    }

    $graphUrl = $page.'@odata.nextLink'
} while ($graphUrl)