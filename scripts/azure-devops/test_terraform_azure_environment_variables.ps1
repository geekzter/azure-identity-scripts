#!/usr/bin/env pwsh

# Test ARM_* environment variables
if ($env:ARM_USE_OIDC -ieq 'true') {
    Write-Host "Testing az login --federated-token"
    az login --service-principal `
             -u $env:ARM_CLIENT_ID `
             --federated-token $env:ARM_OIDC_TOKEN `
             --tenant $env:ARM_TENANT_ID `
             --allow-no-subscriptions
} else {
    Write-Warning "Service connection '$(azureConnection)' is configured to use a secret"
    Write-Host "Testing az login -p"
    az login --service-principal `
             -u $env:ARM_CLIENT_ID `
             -p $env:ARM_CLIENT_SECRET `
             --tenant $env:ARM_TENANT_ID `
             --allow-no-subscriptions
}
  