function Add-ApplicationProperties (
    [parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [object]
    $App
) {
    "https://portal.azure.com/{0}/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/{1}" -f $TenantId, $App.appId | Set-Variable applicationPortalLink
    $App | Add-Member -NotePropertyName applicationPortalLink -NotePropertyValue $applicationPortalLink
}

function Add-ServicePrincipalProperties (
    [parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [object]
    $ServicePrincipal
) {
    $ServicePrincipal | Add-Member -NotePropertyName principalId -NotePropertyValue $ServicePrincipal.id

    if ($ServicePrincipal.servicePrincipalType -eq 'ManagedIdentity') {
        "https://portal.azure.com/#@{0}/resource{1}" -f $TenantId, $ServicePrincipal.alternativeNames[1] | Set-Variable applicationPortalLink
    } else {
        "https://portal.azure.com/{0}/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/{1}" -f $TenantId, $ServicePrincipal.appId | Set-Variable applicationPortalLink
    }
    $ServicePrincipal | Add-Member -NotePropertyName applicationPortalLink -NotePropertyValue $applicationPortalLink

    "https://portal.azure.com/{0}/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/{1}/appId/{2}" -f $TenantId, $ServicePrincipal.id, $ServicePrincipal.appId | Set-Variable servicePrincipalPortalLink
    $ServicePrincipal | Add-Member -NotePropertyName servicePrincipalPortalLink -NotePropertyValue $servicePrincipalPortalLink
}

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

function Decode-JWT (
    [parameter(Mandatory=$true)]
    [string]
    $Token
) {
    if (!$Token) {
        return $null
    }
    try {
        $tokenParts = $Token.Split(".")

        Decode-JWTSegment $tokenParts[0] | Set-Variable tokenHeader
        Write-Debug "Token header:"
        $tokenHeader | Format-List | Out-String | Write-Debug
        Decode-JWTSegment $tokenParts[1] | Set-Variable tokenBody
        Write-Debug "Token body:"
        $tokenBody | Format-List | Out-String | Write-Debug

        return New-Object PSObject -Property @{
            Header = $tokenHeader
            Body = $tokenBody
        }
    } catch {
        Write-Warning "Failed to decode JWT token"
    }
}

function Decode-JWTSegment (
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $TokenSegment
) {
    try {
        if (($TokenSegment.Length % 4) -ne 0) {
            $TokenSegment += ('=' * (4-($TokenSegment.Length % 4)))
        }
        [System.Text.Encoding]::ASCII.GetString([system.convert]::FromBase64String($TokenSegment)) | Set-Variable tokenSegmentJson
        Write-Debug "Token segment JSON:"
        Write-JsonResponse $tokenSegmentJson
        $tokenSegmentJson | ConvertFrom-Json | Set-Variable tokenSegmentObject
        $tokenSegmentObject | Format-List | Out-String | Write-Debug
        return $tokenSegmentObject
    } catch {
        Write-Warning "Failed to decode JWT token segment"
        Write-Debug "Token segment: ${TokenSegment}"
    }
}

function Find-ApplicationByGUID (
    [parameter(Mandatory=$true)][guid]$Id
) {
    if (!$SkipApplication) {
        Write-Debug "az ad app show --id ${Id}"
        az ad app show --id $Id 2>$null | Set-Variable jsonResponse
        if ($jsonResponse) {
            $jsonResponse | ConvertFrom-Json | Set-Variable app
            Write-Verbose "Found Application with Object id '$Id' using:`naz ad app show --id ${Id}"
            Write-JsonResponse -Json $jsonResponse
            return $app
        } else {
            Write-Verbose "No Application found with Object id '$Id'"
        }    
    }

    return $null
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
            Write-Verbose "No Application found with name '$Name'"
        }    
    }

    return $null
}

function Find-ApplicationsByFederation (
    [parameter(Mandatory=$true)]
    [string]
    $StartsWith,

    [parameter(Mandatory=$false)]
    [switch]
    $ExactMatch,

    [parameter(Mandatory=$false)]
    [switch]
    $Details
) {
    Write-Debug "Find-ApplicationsByFederation -StartsWith $StartsWith -ExactMatch $ExactMatch -Details $Details"
    if ($ExactMatch) {
        $filter = "federatedIdentityCredentials/any(f:subject eq '${StartsWith}')"
    } else {
        $filter = "federatedIdentityCredentials/any(f:startsWith(f/subject,'${StartsWith}'))"
    }
    if ($Details) {
        $graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=federatedIdentityCredentials&`$filter=${filter}"
        $jmesPath = "value[]"
    } else {
        $graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=federatedIdentityCredentials&`$filter=${filter}&`$select=id,appId,displayName,federatedIdentityCredentials,keyCredentials,passwordCredentials"
        $jmesPath = "value[].{name:displayName,appId:appId,id:id,federatedSubjects:join(',',federatedIdentityCredentials[].subject),issuers:join(',',federatedIdentityCredentials[].issuer),secretCount:length(passwordCredentials[]),certCount:length(keyCredentials[])}"
    }
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath $jmesPath | Set-Variable apps

    if ($apps) {
        if (!$Details) {
            $apps | Select-Object -Property name,appId,id,federatedSubjects,issuers,secretCount,certCount `
                  | Set-Variable apps
        }
        $apps | Sort-Object -Property name,federatedSubjects `
              | Foreach-Object {
                  Add-ApplicationProperties -App $_
                  $_
                }
              | Set-Variable apps
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual --query `"${jmesPath}`"" -replace "\$","```$" | Write-Verbose
        return $apps
    } else {
        Write-Verbose "No apps found with name starting with '$StartsWith'"
        exit
    }

    return $null
}

function Find-ApplicationsByIssuer (
    [parameter(Mandatory=$true)]
    [string]
    $StartsWith,

    [parameter(Mandatory=$false)]
    [switch]
    $ExactMatch,

    [parameter(Mandatory=$false)]
    [switch]
    $Details,

    [ValidateSet("Application", "ManagedIdentity")]
    [parameter(Mandatory=$true)]
    [string]
    $Type
) {
    Write-Debug "Find-ApplicationsByFederation -StartsWith $StartsWith -ExactMatch $ExactMatch -Details $Details"
    if ($ExactMatch) {
        $filter = "federatedIdentityCredentials/any(f:issuer eq '${StartsWith}')"
    } else {
        $filter = "federatedIdentityCredentials/any(f:startsWith(f/issuer,'${StartsWith}'))"
    }
    if ($Type -eq "Application") {
        $entity = "applications"
    } elseif ($Type -eq "ManagedIdentity") {
        $entity = "servicePrincipals"
    } else {
        Write-Error "Invalid Type '$Type'"
        exit 1
    }
    if ($Details) {
        $graphUrl = "https://graph.microsoft.com/v1.0/${entity}?`$count=true&`$expand=federatedIdentityCredentials&`$filter=${filter}"
        $jmesPath = "value[]"
    } else {
        $graphUrl = "https://graph.microsoft.com/v1.0/${entity}?`$count=true&`$expand=federatedIdentityCredentials&`$filter=${filter}&`$select=id,appId,displayName,federatedIdentityCredentials,keyCredentials,passwordCredentials"
        $jmesPath = "value[].{name:displayName,appId:appId,id:id,federatedSubjects:join(',',federatedIdentityCredentials[].subject),issuers:join(',',federatedIdentityCredentials[].issuer),secretCount:length(passwordCredentials[]),certCount:length(keyCredentials[])}"
    }
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath $jmesPath | Set-Variable apps

    if ($apps) {
        if (!$Details) {
            $apps | Select-Object -Property name,appId,id,federatedSubjects,issuers,secretCount,certCount `
                  | Set-Variable apps
        }
        $apps | Sort-Object -Property name,federatedSubjects`
              | Foreach-Object {
                  Add-ApplicationProperties -App $_
                  $_
                }
              | Set-Variable apps
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual --query `"${jmesPath}`"" -replace "\$","```$" | Write-Verbose
        return $apps
    } else {
        Write-Verbose "No apps found with name starting with '$StartsWith'"
    }

    return $null
}

function Find-ApplicationsByName (
    [parameter(Mandatory=$true)]
    [string]
    $StartsWith
) {
    $graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$filter=startswith(displayName,'${StartsWith}')&`$expand=federatedIdentityCredentials&`$select=id,appId,displayName,federatedIdentityCredentials,keyCredentials,passwordCredentials"
    $jmesPath = "value[].{name:displayName,appId:appId,id:id,federatedSubjects:join(',',federatedIdentityCredentials[].subject),issuers:join(',',federatedIdentityCredentials[].issuer),secretCount:length(passwordCredentials[]),certCount:length(keyCredentials[])}"
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath $jmesPath | Set-Variable apps

    if ($apps) {
        $apps | Select-Object -Property name,appId,id,federatedSubjects,issuers,secretCount,certCount `
              | Sort-Object -Property name `
              | Foreach-Object {
                  Add-ApplicationProperties -App $_
                  $_
                }
              | Set-Variable apps
        Write-Verbose "Found Managed Identity with resourceId '$Id' using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual --query `"${jmesPath}`"" -replace "\$","```$" | Write-Verbose
        return $apps
    } else {
        Write-Verbose "No apps found with name starting with '$StartsWith'"
    }

    return $null
}

function Find-DirectoryObjectsByGraphUrl (
    [parameter(Mandatory=$true)][string]$GraphUrl,
    [parameter(Mandatory=$true)][string]$JmesPath="value"
) {
    $GraphUrl -replace "\$","```$" | Set-Variable graphUrlToDisplay
    Write-Debug "az rest --method get --url `"${graphUrlToDisplay}`" --headers ConsistencyLevel=eventual --query `"${JmesPath}`""
    az rest --method get `
            --url "${GraphUrl} " `
            --headers ConsistencyLevel=eventual `
            --query "${JmesPath} " `
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
    } else {
        Write-Verbose "No objects found"
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
    } else {
        Write-Verbose "No identities found with name starting with '$StartsWith'"
    }

    return $null
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
    } else {
        Write-Verbose "No managed identities found with name starting with '$StartsWith'"
    }

    return $null
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
    } else {
        Write-Verbose "No managed identities found with name containing '$Search'"
    }

    return $null
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
    } else {
        Write-Verbose "No managed identities found with resourceId starting with '${resourcePrefix}'"
    }

    return $null
}

function Find-ManagedIdentityByResourceId (
    [parameter(Mandatory=$true)][string]$Id
) {
    switch -regex ($Id) {
        # Match User-assigned Identity Resource id
        "/subscriptions/(.)+/resourcegroups/(.)+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/(.)+" {
            Write-Verbose "'$Id' is a User-assigned Identity Resource id"
            $IsSysytemIdentity = $false
            $IsUserIdentity = $true
            break
        }
        # Match generic Resource id (System-assigned Identity)
        "/subscriptions/(.)+/resourcegroups/(.)+/(.)+/(.)+" {
            Write-Verbose "'$Id' is a Resource id"
            $IsSysytemIdentity = $true
            $IsUserIdentity = $false
            break
        }
        default {
            Write-Error "'$Id' is not a valid Resource id"
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
    } else {
        Write-Verbose "No Managed Identity found with resourceId '$Id' using Microsoft Graph query:"
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
        } else {
            Write-Verbose "No User-assigned Identity found with resourceId '$Id' using ARM API"
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
        } else {
            Write-Verbose "No System-assigned Identity found with resourceId '$Id' using ARM API"
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
        Add-ServicePrincipalProperties -ServicePrincipal $sp
        Write-Verbose "az ad sp list --filter `"appId eq '${Id}' or id eq '${Id}'`" --query `"[0]`""
        Write-JsonResponse -Json $jsonResponse
        return $sp
    } else {
        Write-Verbose "No Service Principal found with id '$Id'"
    }

    return $null
}

function Find-ServicePrincipalByName (
    [parameter(Mandatory=$true)][string]$Name
) {
    $graphUrl = "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$filter=displayName eq '$Name' or servicePrincipalNames/any(c:c eq '${Name}')"
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath "value[0]" | Set-Variable sp
    if ($sp) {
        if ($sp.displayName -eq $Name) {
            Write-Verbose "Found Service Principal with name '$Name' using Microsoft Graph query:"
        } else {
            Write-Verbose "Found Service Principal with servicePrincipalName '$Name' using Microsoft Graph query:"
        }
        Add-ServicePrincipalProperties -ServicePrincipal $sp
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual" -replace "\$","```$" | Write-Verbose
        return $sp
    } else {
        Write-Verbose "No Service Principal found with name '$Name' using Microsoft Graph query"
    }

    return $null
}

function Get-FederatedCredentials (
    [parameter(Mandatory=$true)]
    [guid]
    $AppId,

    [ValidateSet("Application", "ManagedIdentity")]
    [parameter(Mandatory=$true)]
    [string]
    $Type
) {
    if ($Type -eq "Application") {
        $graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=federatedIdentityCredentials&`$filter=appId eq '${appId}'"
    } elseif ($Type -eq "ManagedIdentity") {
        $graphUrl = "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$expand=federatedIdentityCredentials&`$filter=appId eq '${appId}'"
    } else {
        Write-Error "Invalid Type '$Type'"
        exit 1
    }
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath "value[0].federatedIdentityCredentials[]" | Set-Variable fic
    if ($fic) {
        Write-Verbose "Found Federated Identity Credential(s) using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual" -replace "\$","```$" | Write-Verbose
        return $fic
    } else {
        Write-Verbose "No Federated Identity Credential found for Service Principal with appId '${AppId}' using Microsoft Graph query"
    }

    return $null
}

function Get-ApplicationOwners (
    [parameter(Mandatory=$true)]
    [guid]
    $AppId
) {
    $graphUrl = "https://graph.microsoft.com/v1.0/applications?`$count=true&`$expand=owners&`$filter=appId eq '${appId}'"
    Find-DirectoryObjectsByGraphUrl -GraphUrl $graphUrl -JmesPath "value[0].owners[]" | Set-Variable owners
    if ($owners) {
        Write-Verbose "Found owner(s) using Microsoft Graph query:"
        "az rest --method get --url `"${GraphUrl}`" --headers ConsistencyLevel=eventual" -replace "\$","```$" | Write-Verbose
        return $owners
    } else {
        Write-Verbose "No owner found for Service Principal with appId '${AppId}' using Microsoft Graph query"
    }

    return $null
}

function Get-TerraformDirectory {
    return (Join-Path (Split-Path $PSScriptRoot -Parent) terraform azure-devops create-service-connection)
}

function Invoke (
    [string]$cmd
) {
    Write-Host "`n$cmd" -ForegroundColor Green 
    Invoke-Expression $cmd
    Validate-ExitCode $cmd
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
            az login --allow-no-subscriptions -t $TenantId.Value -o none $($azLoginSwitches)
        } else {
            az login --allow-no-subscriptions $($azLoginSwitches) -o none
            az account show 2>$null | ConvertFrom-Json | Set-Variable azureAccount
            $TenantId.Value = $azureAccount.tenantId
        }
    } else {
        $TenantId.Value = $azureAccount.tenantId
    }
}

function Validate-ExitCode (
    [string]$cmd
) {
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Warning "'$cmd' exited with status $exitCode"
        exit $exitCode
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