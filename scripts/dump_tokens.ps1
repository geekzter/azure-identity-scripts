#!/usr/bin/env pwsh

. (Join-Path $PSScriptRoot functions.ps1)

$azureCliConfigDirectory = $env:AZURE_CONFIG_DIR ?? (Join-Path ~ .azure)

if (!(Test-Path $azureCliConfigDirectory)) {
    Write-Error "Azure config directory '${azureCliConfigDirectory}' does not exist"
    exit 1
}

try {
    Push-Location $azureCliConfigDirectory
    Get-Content msal_token_cache.json | ConvertFrom-Json -AsHashtable | Set-Variable msalTokenCache

    foreach ($token in $msalTokenCache.AccessToken.Values) {
        Decode-JWT $token.secret | Set-Variable jwt
        Write-Host "AccessToken Header:"
        $jwt.Header | Format-List
        Write-Host "AccessToken Body:"
        $jwt.Body | Format-List
    }

    foreach ($token in $msalTokenCache.IdToken.Values) {
        Decode-JWT $token.secret | Set-Variable jwt
        Write-Host "idToken Header:"
        $jwt.Header | Format-List
        Write-Host "idToken Body:"
        $jwt.Body | Format-List
    }
} finally {
    Pop-Location
}