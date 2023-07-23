terraform {
  required_providers {
    azuread                    = "~> 2.40"
    azuredevops = {
      source                   = "microsoft/azuredevops"
      version                  = "~> 0.7"
    }
    azurerm                    = "~> 3.66"
    external                   = "~> 2.3"
    http                       = "~> 3.4"
    random                     = "~> 3.5"
  }
  required_version             = "~> 1.3"
}

data external azdo_token {
  program                      = [
    "az", "account", "get-access-token", 
    "--resource", "499b84ac-1321-427f-aa17-267ca6975798", # Azure DevOps
    "-o","json"
  ]
}
provider azuredevops {
  org_service_url              = local.azdo_organization_url
  personal_access_token        = data.external.azdo_token.result.accessToken
}

provider azurerm {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider azurerm {
  alias                        = "managed_identity"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id              = local.managed_identity_subscription_id
}

provider azurerm {
  alias                        = "target"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id              = local.target_subscription_id
}