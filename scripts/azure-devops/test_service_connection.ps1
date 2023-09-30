#!/usr/bin/env pwsh
<# 
.SYNOPSIS 
    Test service connection.

.DESCRIPTION 
    Test service connection. This script is meant to be run from a pipeline, and runs another pipeline to test a newly created/converted service connection.

#> 
#Requires -Version 7.2

param ( 

    [parameter(Mandatory=$true,HelpMessage="Name of the Service Connection")]
    [string]
    [ValidateNotNullOrEmpty()]
    $ServiceConnectionName,

    [parameter(Mandatory=$true)]
    [int]
    [ValidateNotNullOrEmpty()]
    $ServiceConnectionTestPipelineId,

    [parameter(Mandatory=$false,HelpMessage="Name of the Azure DevOps Project")]
    [string]
    [ValidateNotNullOrEmpty()]
    $Project=$env:SYSTEM_TEAMPROJECT,

    [parameter(Mandatory=$false,HelpMessage="Url of the Azure DevOps Organization")]
    [uri]
    [ValidateNotNullOrEmpty()]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI)
) 
Write-Verbose $MyInvocation.line 
. (Join-Path $PSScriptRoot .. functions.ps1)

Write-Host "Using service connection '${ServiceConnectionName}'"

az devops configure --defaults organization=$OrganizationUrl project="${Project}"

Write-Host "Authorizing the service connection to use the pipeline..."
az devops service-endpoint list --query "[?name=='${ServiceConnectionName}'].id" `
                                -o tsv `
                                | Set-Variable serviceConnectionId
if (!$serviceConnectionId) {
  Write-Host "##vso[task.LogIssue type=error]Service connection '${ServiceConnectionName}' not found."
  Write-Error "Service connection '${ServiceConnectionName}' not found."
  exit 1
}
az devops service-endpoint update --id $serviceConnectionId `
                                  --enable-for-all true

Write-Host "Running the test pipeline with parameter serviceConnection=${ServiceConnectionName}..."
az pipelines run --id $ServiceConnectionTestPipelineId `
                 --parameters serviceConnection="${ServiceConnectionName}" `
                 -o json `
                 | ConvertFrom-Json `
                 | Set-Variable run
$run | ConvertTo-Json | Out-String | Write-Debug
$run | Format-List | Out-String | Write-Debug
"{0}{1}/_build/results?buildId={2}&view=results" -f "$(System.CollectionUri)", [uri]::EscapeDataString("$(System.TeamProject)"), $run.id | Write-Host
Write-Host "Waiting for pipeline run $($run.id) to complete..."
do {
    Start-Sleep -Seconds 5
    az pipelines runs show --id $run.id `
                           -o json `
                           | ConvertFrom-Json `
                           | Set-Variable run
    $run | ConvertTo-Json | Out-String | Write-Debug
    $run | Format-List | Out-String | Write-Debug
    # pause
    Write-Host "Run status: $($run.status)"
} while ($run.status -ne 'completed')
Write-Host "Run result: $($run.result)"

if ($run.result -notmatch 'succeeded') {
    Write-Host "##vso[task.LogIssue type=error]Service Connection test job failed with result: $($run.result)"
    Write-Error "Run failed with result: $($run.result)"
    exit 1
}