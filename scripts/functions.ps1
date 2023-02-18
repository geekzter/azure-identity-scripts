function Find-ApplicationByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    if ($FindApplication) {
        az ad app show --id $Id 2>$null | ConvertFrom-Json | Set-Variable app
        if ($app) {
            Write-Verbose "Found Application with Object ID '$Id' using:`naz ad app show --id ${Id}"
            return $app
        } else {
            return $null
        }    
    }
}

function Find-ApplicationByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    if ($FindApplication) {
        az ad app list --display-name $Name --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable app
        if ($app) {
            Write-Verbose "Found Application with name '$Name' using:`naz ad app list --display-name ${Name}"
            return $app
        } else {
            return $null
        }            
    }
}

function Find-ServicePrincipalByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    az ad sp show --id $Id 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Verbose "Found Service Principal with Object ID '$Id' using:`naz ad sp show --id ${Id}"
    } else {
        az ad sp list --filter "appId eq '$Id'" --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
        if ($sp) {
            Write-Verbose "Found Service Principal with Application ID '$Id' using:`naz ad sp list --filter `"appId eq '${Id}'`" --query `"[0]`""
        }
    }

    return $sp
}

function Find-ManagedIdentitiesByNameMicrosoftGraph (
    [parameter(Mandatory=$true)][string]$StartsWith
) {
    if ($ManagedIdentityType -eq "UserCreated") {
        $jmesPathQuery = "?contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } elseif ($ManagedIdentityType -eq "SystemCreated") {
        $jmesPathQuery = "?!contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } else {
        $jmesPathQuery = ""
    }

    Write-Debug "az ad sp list --filter `"startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
    az ad sp list --filter "startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'" `
                  --query "[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}" `
                  -o json `
                  | Set-Variable jsonResponse
    if ($jsonResponse) {
        if (Get-Command jq -ErrorAction SilentlyContinue) {
            Write-Debug "resposne:"
            $jsonResponse | jq -C | Write-Debug
        }
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable sps
        Write-Verbose "Found $(($sps | Measure-Object).Count) Managed Identities with name starting with '$StartsWith' using:"
        Write-Verbose "az ad sp list --filter `"startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
        return $sps
    }
}

function Find-ManagedIdentitiesByNameAzureResourceGraph (
    [parameter(Mandatory=$true)][string]$Search
) {
    if (!(az extension list --query "[?name=='resource-graph'].version" -o tsv)) {
        Write-Host "Adding Azure CLI extension 'resource-graph'..."
        az extension add -n resource-graph -y
    }
    
    $userAssignedGraphQuery = "Resources | where type =~ 'Microsoft.ManagedIdentity/userAssignedIdentities' and name contains '${Search}' | extend sp = parse_json(properties) | project name=name,appId=sp.clientId,principalId=sp.principalId,resourceId=id | order by name asc"
    $systemGraphQuery = "Resources | where name contains '${Search}' | extend principalId=parse_json(identity).principalId | where isnotempty(principalId) | project name=name,appId='',principalId,resourceId=id | order by name asc"
    if ($ManagedIdentityType -eq "UserCreated") {
        $resourceGraphQuery = $userAssignedGraphQuery
    } elseif ($ManagedIdentityType -eq "SystemCreated") {
        $resourceGraphQuery = $systemGraphQuery
    } else {
        $resourceGraphQuery = "${userAssignedGraphQuery} | union (${systemGraphQuery}) | order by name asc"
    }
    Write-Debug "az graph query -q `"${resourceGraphQuery}`" -a --query `"data`""
    az graph query -q $resourceGraphQuery `
                   -a `
                   --query "data" `
                   -o json `
                   | Set-Variable jsonResponse
    if ($jsonResponse) {
        if (Get-Command jq -ErrorAction SilentlyContinue) {
            Write-Debug "resposne:"
            $jsonResponse | jq -C | Write-Debug
        }
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable mis
        Write-Verbose "Found $(($mis | Measure-Object).Count) Managed Identities with name containing '$Search' using:"
        Write-Verbose "az graph query -q `"${resourceGraphQuery}`" -a --query `"data`""
        return $mis
    }
}

function Find-ManagedIdentityByResourceID (
    [parameter(Mandatory=$true)][string]$Id
) {
    switch -regex ($Id) {
        # Match User-assigned Identity Resource ID
        "/subscriptions/(.)+/resourcegroups/(.)+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/(.)+" {
            Write-Verbose "'$Id' is a User-assigned Identity Resource ID"
            $IsSysytemIdentity = $false
            $IsUserIdentity = $true
            break
        }
        # Match generic Resource ID (System-assigned Identity)
        "/subscriptions/(.)+/resourcegroups/(.)+/(.)+/(.)+" {
            Write-Verbose "'$Id' is a Resource ID"
            $IsSysytemIdentity = $true
            $IsUserIdentity = $false
            break
        }
        default {
            Write-Error "'$Id' is not a valid Resource ID"
            exit
        }
    }
    # Try Microsoft Graph
    $graphUrl = "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=alternativeNames/any(p:p eq '${Id}')"
    az rest --method get `
            --url $graphUrl `
            --headers ConsistencyLevel=eventual `
            --query "value[0]" `
            -o json `
            | ConvertFrom-Json `
            | Set-Variable sp
    if ($sp) {
        $sp | Add-Member -NotePropertyName principalId -NotePropertyValue $sp.id
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        Write-Verbose "az rest --method get --url `"${graphUrl}`" --headers ConsistencyLevel=eventual"
        return $sp
    }

    # Use ARM API for User-assigned Identity
    if ($IsUserIdentity) {
        az identity show --ids $Id -o json 2>$null | ConvertFrom-Json | Set-Variable mi
        if ($mi) {
            Write-Verbose "Found User-assigned Identity with resourceId '$Id' using ARM API:"
            Write-Verbose "az identity show --ids $Id"
            return $mi
        }    
    }

    # Use ARM API for System-assigned Identity
    if ($IsSysytemIdentity) {
        az resource show --ids $Id --query "{id:id, principalId:identity.principalId, tenantId:tenantId}" -o json 2>$null | Set-Variable mi
        if ($mi) {
            Write-Verbose "Found System-managed Identity with resourceId '$Id' using ARM API:"
            Write-Verbose "az resource show --ids $Id --query `"identity`" -o tsv"
            return $mi
        }
    }
}

function Find-ServicePrincipalByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    az ad sp show --id $Name 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Verbose "Found Service Principal with Application ID '$Name' using:"
        Write-Verbose "az ad sp show --id $Name"
        return $sp
    } 
    az ad sp list --filter "displayName eq '$Name'" --query "[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Verbose "Found Service Principal with Display Name '$Name' using:"
        Write-Verbose "az ad sp list --filter `"displayName eq '$Name'`""
        return $sp
    } 
    az ad sp show --spn $Name 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Verbose "Found Service Principal with Service Principal Name (SPN) '$Name' using:"
        Write-Verbose "az ad sp show --spn $Name"
        return $sp
    } 
    az ad sp list --show-mine --query "[?contains(servicePrincipalNames,'$Name')]|[0]" 2>$null | ConvertFrom-Json | Set-Variable sp
    if ($sp) {
        Write-Verbose "Found my Service Principal with '$Name' using Azure CLI JMESPath:"
        Write-Verbose "az ad sp list --show-mine --query `[?contains(servicePrincipalNames,'$Name')]|[0]`""
        return $sp
    }
}

function Login-Az (
    [parameter(Mandatory=$false)][ref]$TenantId=($env:ARM_TENANT_ID ?? $env:AZURE_TENANT_ID)
) {
    if (!(Get-Command az)) {
        Write-Error "Azure CLI is not installed, get it at http://aka.ms/azure-cli"
        exit 1
    }

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