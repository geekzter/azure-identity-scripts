function Login-Az (
    [parameter(Mandatory=$false)][ref]$TenantId=$env:ARM_TENANT_ID
) {

    # Are we logged into the wrong tenant?
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        if ($TenantId.Value -and ($TenantId.Value -ne [guid]::Empty.ToString())) {
            $script:loggedInTenantId = $(az account show --query tenantId -o tsv 2>$null)
        }
    }
    if ($loggedInTenantId -and ($loggedInTenantId -ine $TenantId.Value)) {
        Write-Warning "Logged into tenant $loggedInTenantId instead of $($TenantId.Value), logging off az session"
        az logout -o none
    }

    # Are we logged in?
    Invoke-Command -ScriptBlock {
        $Private:ErrorActionPreference = "Continue"
        # Test whether we are logged in
        $script:loginError = $(az account show -o none 2>&1)
        if (!$loginError) {
            $Script:userType = $(az account show --query "user.type" -o tsv)
            if ($userType -ieq "user") {
                # Test whether credentials have expired
                $Script:userError = $(az ad signed-in-user show -o none 2>&1)
            } 
        }
    }

    # Do we need to log in?
    $login = ($loginError -or $userError)

    # Logging in
    if ($login) {
        if ($TenantId.Value) {
            Write-Debug "Azure Active Directory Tenant ID is '$($TenantId.Value)'"
            az login -t $TenantId.Value -o none
        } else {
            Write-Host "Azure Active Directory Tenant ID not explicitely set"
            az login -o none
            $TenantId.Value = $(az account show --query tenantId -o tsv)
        }
        Write-Verbose "Using Azure Active Directory Tenant '$($TenantId.Value)'"
    }
}