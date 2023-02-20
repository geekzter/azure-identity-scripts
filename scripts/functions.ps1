function Create-IdentityTypeJmesPathQuery (
    [parameter(Mandatory=$false)]
    [ValidateSet("UserCreatedManagedIdentity", "SystemCreatedManagedIdentity", "Any")]
    [string]
    $IdentityType
) {
    if ($IdentityType -eq "UserCreatedManagedIdentity") {
        $jmesPathQuery = "?contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } elseif ($IdentityType -eq "SystemCreatedManagedIdentity") {
        $jmesPathQuery = "?!contains(alternativeNames[1],'Microsoft.ManagedIdentity')"
    } else {
        $jmesPathQuery = ""
    }

    return $jmesPathQuery
}

function Find-ApplicationByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    if (!$SkipApplication) {
        Write-Debug "az ad app show --id ${Id}"
        az ad app show --id $Id 2>$null | Set-Variable jsonResponse
        if ($jsonResponse) {
            $jsonResponse | ConvertFrom-Json | Set-Variable app
            Write-Verbose "Found Application with Object ID '$Id' using:`naz ad app show --id ${Id}"
            Write-JsonResponse -Json $jsonResponse
            return $app
        } else {
            return $null
        }    
    }
}

function Find-ApplicationByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    if (!$SkipApplication) {
        Write-Debug "az ad app list --display-name $Name --query `"[0]`""
        az ad app list --display-name $Name --query "[0]" 2>$null | Set-Variable jsonResponse
        if ($jsonResponse) {
            $jsonResponse | ConvertFrom-Json | Set-Variable app
            Write-Verbose "Found Application with name '$Name' using:`naz ad app list --display-name ${Name}"
            Write-JsonResponse -Json $jsonResponse
            return $app
        } else {
            return $null
        }    
    }
}

function Find-ApplicationsByName (
    [parameter(Mandatory=$true)]
    [string]
    $StartsWith
) {
    $graphUrl = "https://graph.microsoft.com/v1.0/applications?$count=true&`$filter=startswith(displayName,'${StartsWith}')&`$expand=federatedIdentityCredentials&`$select=id,appId,displayName,federatedIdentityCredentials,keyCredentials,passwordCredentials"
    $jmesPath = "value[].{name:displayName,appId:appId,id:id,federationSubjects:join(',',federatedIdentityCredentials[].subject),passwordCredentials:length(passwordCredentials[]),keyCredentials:length(keyCredentials[])}"
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath $jmesPath | Set-Variable apps

    if ($apps) {
        $apps | Select-Object -Property name,appId,id,federationSubjects,keyCredentials,passwordCredentials `
              | Sort-Object -Property name `
              | Set-Variable apps
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual --query `"${jmesPath}`"" -replace "\$","```$" | Write-Verbose
        return $apps
    }
}

function Find-DirectoryObjectsByGraphUrl (
    [parameter(Mandatory=$true)][string]$GraphUrl,
    [parameter(Mandatory=$true)][string]$JmesPath="value"
) {
    $GraphUrl -replace "\$","```$" | Set-Variable graphUrlToDisplay
    Write-Debug "az rest --method get --url `"${graphUrlToDisplay}`" --headers ConsistencyLevel=eventual --query `"${JmesPath}`""
    az rest --method get `
            --url $GraphUrl `
            --headers ConsistencyLevel=eventual `
            --query $JmesPath `
            -o json `
            | Set-Variable jsonResponse
    if ($jsonResponse) {
        $jsonResponse | ConvertFrom-Json `
                      | Set-Variable directoryObject
        Write-Verbose "az rest --method get --url `"${graphUrlToDisplay}`" --headers ConsistencyLevel=eventual --query `"${JmesPath}`""
        Write-JsonResponse -Json $jsonResponse
        if ($directoryObject -is [array]) {
            $directoryObject | Format-Table -AutoSize | Out-String | Write-Debug
        } else {
            $directoryObject | Format-List | Out-String | Write-Debug
        }
        return $directoryObject
    }

    return $null
}

function Find-IdentitiesByNameMicrosoftGraph (
    [parameter(Mandatory=$true)]
    [string]
    $StartsWith,

    [parameter(Mandatory=$false)]
    [ValidateSet("Any", "ServicePrincipal", "SystemCreatedManagedIdentity", "UserCreatedManagedIdentity")]
    [string]
    $IdentityType="Any"
) {
    switch ($IdentityType) {
        "Any" {
            $filter = "startswith(displayName,'${StartsWith}')"
            $jmesPathQuery = $null
        }
        "ServicePrincipal" {
            $filter = "startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'Application'"
            $jmesPathQuery = $null
        }
        default {
            $filter = "startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'"
            Create-IdentityTypeJmesPathQuery -IdentityType $IdentityType | Set-Variable jmesPathQuery
        } 
    }   

    Write-Debug "az ad sp list --filter `"${filter}`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
    az ad sp list --filter "${filter}" `
                  --query "[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}" `
                  -o json `
                  | Set-Variable jsonResponse
    if ($jsonResponse) {
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable sps
        Write-Verbose "Found $(($sps | Measure-Object).Count) Identities of type '${Type}' and with name starting with '$StartsWith' using:"
        Write-Verbose "az ad sp list --filter `"${filter}`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
        Write-JsonResponse -Json $jsonResponse
        return $sps
    }
}

function Find-ManagedIdentitiesByNameMicrosoftGraph (
    [parameter(Mandatory=$true)][string]$StartsWith
) {
    Create-IdentityTypeJmesPathQuery -IdentityType $IdentityType | Set-Variable jmesPathQuery
    Write-Debug "az ad sp list --filter `"startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
    az ad sp list --filter "startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'" `
                  --query "[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}" `
                  -o json `
                  | Set-Variable jsonResponse
    if ($jsonResponse) {
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable sps
        Write-Verbose "Found $(($sps | Measure-Object).Count) Managed Identities with name starting with '$StartsWith' using:"
        Write-Verbose "az ad sp list --filter `"startswith(displayName,'${StartsWith}') and servicePrincipalType eq 'ManagedIdentity'`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
        Write-JsonResponse -Json $jsonResponse
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
    if ($IdentityType -eq "UserCreatedManagedIdentity") {
        $resourceGraphQuery = $userAssignedGraphQuery
    } elseif ($IdentityType -eq "SystemCreatedManagedIdentity") {
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
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable mis
        Write-Verbose "Found $(($mis | Measure-Object).Count) Managed Identities with name containing '$Search' using:"
        Write-Verbose "az graph query -q `"${resourceGraphQuery}`" -a --query `"data`""
        Write-JsonResponse -Json $jsonResponse
        return $mis
    }
}

function Find-ManagedIdentitiesBySubscription (
    [parameter(Mandatory=$true)][guid]$SubscriptionId,
    [parameter(Mandatory=$false)][string]$ResourceGroupNameOrPrefix
)
{
    $resourcePrefix = "/subscriptions/${SubscriptionId}"
    if ($ResourceGroupNameOrPrefix) {
        $resourcePrefix += "/resourcegroups/${ResourceGroupNameOrPrefix}"
    }

    Create-IdentityTypeJmesPathQuery -IdentityType $IdentityType | Set-Variable jmesPathQuery
    Write-Debug "az ad sp list --filter `"servicePrincipalType eq 'ManagedIdentity' and alternativeNames/any(p:startsWith(p,'${resourcePrefix}'))`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table"
    az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity' and alternativeNames/any(p:startsWith(p,'${resourcePrefix}'))" `
                  --query "[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}" `
                  -o json `
                  | Set-Variable jsonResponse
    if ($jsonResponse) {
        $jsonResponse | ConvertFrom-Json `
                      | Select-Object -Property name,appId,principalId,resourceId `
                      | Sort-Object -Property name `
                      | Set-Variable mis
        Write-Verbose "Found $(($mis | Measure-Object).Count) Managed Identities with resourceId starting with '${resourcePrefix}' using Microsoft Graph query:"
        "az ad sp list --filter `"servicePrincipalType eq 'ManagedIdentity' and alternativeNames/any(p:startsWith(p,'${resourcePrefix}'))`" --query `"[${jmesPathQuery}].{name:displayName,appId:appId,principalId:id,resourceId:alternativeNames[1]}`" -o table" | Write-Verbose
        Write-JsonResponse -Json $jsonResponse
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
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath "value[0]" | Set-Variable sp
    if ($sp) {
        $sp | Add-Member -NotePropertyName principalId -NotePropertyValue $sp.id
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual" -replace "\$","```$" | Write-Verbose
        return $sp
    }

    # Use ARM API for User-assigned Identity
    if ($IsUserIdentity) {
        Write-Debug "az identity show --ids $Id"
        az identity show --ids $Id -o json 2>$null | Set-Variable jsonResponse
        if ($jsonResponse) {
            $jsonResponse | ConvertFrom-Json `
                          | Set-Variable mi
            Write-Verbose "Found User-assigned Identity with resourceId '$Id' using ARM API:"
            Write-Verbose "az identity show --ids $Id"
            Write-JsonResponse -Json $jsonResponse
            return $mi
        }
    }

    # Use ARM API for System-assigned Identity
    if ($IsSysytemIdentity) {
        Write-Debug "az resource show --ids $Id --query `"{id:id, principalId:identity.principalId, tenantId:tenantId}`""
        az resource show --ids $Id --query "{id:id, principalId:identity.principalId, tenantId:tenantId}" -o json 2>$null | Set-Variable jsonResponse
        if ($jsonResponse) {
            $jsonResponse | ConvertFrom-Json `
                          | Set-Variable mi
            Write-Verbose "Found System-assigned Identity with resourceId '$Id' using ARM API:"
            Write-Verbose "az resource show --ids $Id --query `"identity`" -o tsv"
            Write-JsonResponse -Json $jsonResponse
            return $mi
        }
    }
}

function Find-ServicePrincipalByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    Write-Debug "az ad sp list --filter `"appId eq '${Id}' or id eq '${Id}'`" --query `"[0]`""
    az ad sp list --filter "appId eq '$Id' or id eq '$Id'" --query "[0]" 2>$null | Set-Variable jsonResponse
    if ($jsonResponse) {
        $jsonResponse | ConvertFrom-Json | Set-Variable sp
        if ($sp.id -eq $Id) {
            Write-Verbose "Found Service Principal with id '$Id' using:"
        } elseif ($sp.appId -eq $Id) {
            Write-Verbose "Found Service Principal with appId '$Id' using:"
        }
        Write-Verbose "az ad sp list --filter `"appId eq '${Id}' or id eq '${Id}'`" --query `"[0]`""
        Write-JsonResponse -Json $jsonResponse
        return $sp
    }    

    return $null
}

function Find-ServicePrincipalByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    $graphUrl = "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=displayName eq '$Name' or servicePrincipalNames/any(c:c eq '${Name}')"
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath "value[0]" | Set-Variable sp
    if ($sp) {
        $sp | Add-Member -NotePropertyName principalId -NotePropertyValue $sp.id
        if ($sp.displayName -eq $Name) {
            Write-Verbose "Found Service Principal with name '$Name' using Microsoft Graph query:"
        } else {
            Write-Verbose "Found Service Principal with servicePrincipalName '$Name' using Microsoft Graph query:"
        }
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual" -replace "\$","```$" | Write-Verbose
        return $sp
    }

    return $null
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
            Write-Debug "az login -t $TenantId.Value $($azLoginSwitches)"
            az login -t $TenantId.Value -o none $($azLoginSwitches)
        } else {
            az login $($azLoginSwitches) -o none
            az account show 2>$null | ConvertFrom-Json | Set-Variable azureAccount
            $TenantId.Value = $azureAccount.tenantId
        }
    }
}

function Write-JsonResponse (
    [parameter(Mandatory=$true)]
    [ValidateNotNull()]
    $Json
) {
    if (Get-Command jq -ErrorAction SilentlyContinue) {
        $Json | jq -C | Write-Debug
    } else {
        Write-Debug $Json
    }
}