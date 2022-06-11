function Login-Az (
    [parameter(Mandatory=$false)][ref]$TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) {

    # Are we logged in? If so, is it the right tenant?
    $azureAccount = $null
    az account show 2>$null | ConvertFrom-Json | Set-Variable azureAccount
    if ($azureAccount   -and `
        $TenantId.Value -and `
        ($TenantId.Value -ne [guid]::Empty.ToString()) -and `
        ($azureAccount.tenantId -ine $TenantId.Value)) {
        Write-Warning "Logged into tenant $($azureAccount.tenant_id) instead of $($TenantId.Value)"
        $azureAccount = $null
    }
    if (-not $azureAccount) {
        if ($env:CODESPACES -ieq "true") {
            $azLoginSwitches = "--use-device-code"
        }
        if ($TenantId.Value -and ($TenantId.Value -ne [guid]::Empty.ToString())) {
            az login -t $TenantId.Value -o none $($azLoginSwitches)
        } else {
            az login $($azLoginSwitches) -o none
            az account show 2>$null | ConvertFrom-Json | Set-Variable azureAccount
            $TenantId.Value = $azureAccount.tenantId
        }
    }
}