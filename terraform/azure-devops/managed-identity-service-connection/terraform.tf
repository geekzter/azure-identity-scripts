terraform {
  required_providers {
    azuread                    = "~> 2.40"
    azuredevops = {
      source                   = "microsoft/azuredevops"
      version                  = "~> 0.7"
    }
    azurerm                    = "~> 3.66"
    # http                       = "~> 2.2"
    # local                      = "~> 2.3"
    random                     = "~> 3.5"
    # time                       = "~> 0.9"
  }
  required_version             = "~> 1.3"
}

# provider azuredevops {
#   org_service_url              = local.azdo_organization_url
#   personal_access_token        = var.devops_pat
# }
provider azurerm {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
