data azurerm_client_config current {}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource random_string suffix {
  length                       = 4
  upper                        = false
  lower                        = true
  numeric                      = false
  special                      = false
}

locals {
  application_id               = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.application_id : module.service_principal.0.application_id)
  authentication_scheme        = var.create_federation ? "WorkloadIdentityFederation" : "ServicePrincipal"
  azdo_organization_name       = split("/",var.azdo_organization_url)[3]
  azdo_organization_url        = replace(var.azdo_organization_url,"/\\/$/","")
  azdo_project_url             = "${local.azdo_organization_url}/${urlencode(var.azdo_project_name)}"
  azdo_service_connection_name = "${replace(module.azure_access.subscription_name,"/ +/","-")}-${var.azdo_creates_identity ? "aut" : "man"}-${var.create_managed_identity ? "msi" : "sp"}-${var.create_federation ? "oidc" : "secret"}${terraform.workspace == "default" ? "" : format("-%s",terraform.workspace)}-${local.resource_suffix}"
  azure_scope                  = var.azure_scope != null && var.azure_scope != "" ? var.azure_scope : "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  principal_id                 = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.principal_id : module.service_principal.0.principal_id)
  principal_name               = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.principal_name : module.service_principal.0.principal_name)
  resource_suffix              = var.resource_suffix != null && var.resource_suffix != "" ? lower(var.resource_suffix) : random_string.suffix.result
  resource_tags                = {
    application                = "Azure Service Connection"
    githubRepo                 = "https://github.com/geekzter/azure-identity-scripts"
    provisioner                = "terraform"
    provisionerClientId        = data.azurerm_client_config.current.client_id
    provisionerObjectId        = data.azurerm_client_config.current.object_id
    repository                 = "azure-identity-scripts"
    runId                      = var.run_id
    workspace                  = terraform.workspace
  }
  managed_identity_subscription_id = var.create_managed_identity ? split("/", var.managed_identity_resource_group_id)[2] : null
  target_subscription_id       = split("/", local.azure_scope)[2]
}

resource terraform_data managed_identity_validator {
  triggers_replace             = [
    var.create_managed_identity,
    var.managed_identity_resource_group_id
  ]

  lifecycle {
    precondition {
      condition                = var.create_managed_identity && can(split("/", var.managed_identity_resource_group_id)[4])
      error_message            = "managed_identity_resource_group_id is required when create_managed_identity is true"
    }
  }

  count                        = var.create_managed_identity ? 1 : 0  
}

module managed_identity {
  providers                    = {
    azurerm                    = azurerm.managed_identity
  }
  source                       = "./modules/managed-identity"
  federation_subject           = module.service_connection.service_connection_oidc_subject
  issuer                       = module.service_connection.service_connection_oidc_issuer
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.resource_suffix}"
  resource_group_name          = split("/", var.managed_identity_resource_group_id)[4]
  tags                         = local.resource_tags

  count                        = var.create_managed_identity ? 1 : 0
  depends_on                   = [terraform_data.managed_identity_validator]
}

module service_principal {
  source                       = "./modules/service-principal"
  create_federation            = var.create_federation
  description                  = "Azure DevOps Service Connection ${local.azdo_service_connection_name}${var.entra_secret_expiration_days == 0 ? " (with short-lived secret)" : " "} in project ${local.azdo_project_url}. Managed by Terraform: https://github.com/geekzter/azure-identity-scripts/tree/main/terraform/azure-devops/create-service-connection."
  federation_subject           = var.create_federation ? module.service_connection.service_connection_oidc_subject : null
  issuer                       = var.create_federation ? module.service_connection.service_connection_oidc_issuer : null
  multi_tenant                 = false
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.resource_suffix}"
  owner_object_ids             = var.entra_owner_object_ids
  secret_expiration_days       = var.entra_secret_expiration_days
  service_management_reference = var.entra_service_management_reference

  count                        = var.create_managed_identity || var.azdo_creates_identity ? 0 : 1
}

module azure_access {
  providers                    = {
    azurerm                    = azurerm.target
  }
  source                       = "./modules/azure-access"
  create_role_assignment       = !var.azdo_creates_identity
  identity_object_id           = local.principal_id
  resource_id                  = local.azure_scope
  role                         = var.azure_role
}

module service_connection {
  source                       = "./modules/service-connection"
  application_id               = local.application_id
  application_secret           = var.azdo_creates_identity || var.create_federation ? null : module.service_principal.0.secret
  authentication_scheme        = local.authentication_scheme
  create_identity              = var.azdo_creates_identity
  project_name                 = var.azdo_project_name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  service_connection_name      = local.azdo_service_connection_name
  subscription_id              = local.target_subscription_id
  subscription_name            = module.azure_access.subscription_name
}
