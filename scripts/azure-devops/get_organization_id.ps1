#!/usr/bin/env pwsh
#Requires -Version 7
param ( 
    [parameter(Mandatory=$true,ParameterSetName="Organization",HelpMessage="Name of the Azure DevOps Organization")]
    [ValidateNotNullOrEmpty()]
    [string]
    $OrganizationUrl=($env:AZDO_ORG_SERVICE_URL ?? $env:SYSTEM_COLLECTIONURI)
) 

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')

$projectCollectionsUrl = "${OrganizationUrl}/_apis/projectCollections?api-version=7.1-preview.1"
Write-Host $projectCollectionsUrl
az rest --method get `
        --uri $projectCollectionsUrl `
        --resource 499b84ac-1321-427f-aa17-267ca6975798 `
        -o json

$connectionDataUrl = "${OrganizationUrl}/_apis/connectionData?api-version=7.1-preview.1"
Write-Host $connectionDataUrl
az rest --method get `
        --uri $connectionDataUrl `
        --resource 499b84ac-1321-427f-aa17-267ca6975798 `
        -o json `
        | Tee-Object -Variable connectionDataJson `
        | ConvertFrom-Json `
        | Set-Variable connectionData
$connectionDataJson | jq

$profileUrl = "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1-preview.1"
Write-Host $profileUrl
az rest --method get `
        --uri $profileUrl `
        --resource 499b84ac-1321-427f-aa17-267ca6975798 `
        -o json `
        | Tee-Object -Variable profileJson `
        | ConvertFrom-Json `
        | Set-Variable profile
$profileJson | jq

$accountsUrl = "https://app.vssps.visualstudio.com/_apis/accounts?api-version=7.1-preview.1&memberId=$($profile.id)"
# $accountsUrl = "https://app.vssps.visualstudio.com/_apis/accounts?api-version=7.1-preview.1&memberId=$($connectionData.authenticatedUser.id)"
Write-Host $accountsUrl
az rest --method get `
        --uri $accountsUrl `
        --resource 499b84ac-1321-427f-aa17-267ca6975798 `
        -o json `
        | Tee-Object -Variable accountsJson `
        | ConvertFrom-Json `
        | Set-Variable accounts
$accountsJson | jq

Write-Host "`nObtaining access token for Service Connection identity..."
# 499b84ac-1321-427f-aa17-267ca6975798 is the Azure DevOps resource ID
Write-Host "$($PSStyle.Formatting.FormatAccent)az account get-access-token$($PSStyle.Reset)"
az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 `
                            --query "accessToken" `
                            --output tsv `
                            | Set-Variable aadToken
