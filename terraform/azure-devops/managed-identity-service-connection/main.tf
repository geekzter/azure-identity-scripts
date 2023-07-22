data azuread_client_config current {}

data external azdo_token {
  program                      = [
    "az", 
    "account", 
    "get-access-token", 
    "--resource", 
    "499b84ac-1321-427f-aa17-267ca6975798"
  ]
}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource random_string suffix {
  length                       = 4
  upper                        = false
  lower                        = true
  numeric                      = false
  special                      = false
}

locals {
  application_id               = var.create_managed_identity ? module.managed_identity.0.application_id : module.service_principal.0.application_id
  azdo_organization_url        = replace(var.azdo_organization_url,"/\\/$/","")
  azdo_organization_name       = replace(var.azdo_organization_url,"/.*dev.azure.com//","")
  azdo_service_connection_name = "msi-oidc-${terraform.workspace}-${local.suffix}"
  federation_subject           = "sc://${local.azdo_organization_name}/${var.azdo_project_name}/${local.azdo_service_connection_name}"
  principal_id                 = var.create_managed_identity ? module.managed_identity.0.principal_id : module.service_principal.0.principal_id
  principal_name               = var.create_managed_identity ? module.managed_identity.0.principal_name : module.service_principal.0.principal_name
  issuer                       = "https://app.vstoken.visualstudio.com"
  suffix                       = random_string.suffix.result
  managed_identity_subscription_id = split("/", var.managed_identity_resource_group_id)[2]
  target_subscription_id       = split("/", var.azure_resource_id)[2]
}

module managed_identity {
  providers                    = {
    azurerm                    = azurerm.managed_identity
  }
  source                       = "./modules/managed-identity"
  federation_subject           = local.federation_subject
  issuer                       = local.issuer
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.suffix}"
  resource_group_name          = split("/", var.managed_identity_resource_group_id)[4]

  count                        = var.create_managed_identity ? 1 : 0
}

module service_principal {
  source                       = "./modules/service-principal"
  federation_subject           = local.federation_subject
  issuer                       = local.issuer
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.suffix}"

  count                        = var.create_managed_identity ? 0 : 1
}

module azure_access {
  providers                    = {
    azurerm                    = azurerm.target
  }
  source                       = "./modules/azure-access"
  identity_object_id           = local.principal_id
  resource_id                  = var.azure_resource_id
  role                         = var.azure_role
}

module service_connection {
  source                       = "./modules/service-connection"
  application_id               = local.application_id
  project_name                 = var.azdo_project_name
  tenant_id                    = var.create_managed_identity ? module.managed_identity.0.tenant_id : module.service_principal.0.tenant_id
  service_connection_name      = local.azdo_service_connection_name
  subscription_id              = local.target_subscription_id
  subscription_name            = module.azure_access.subscription_name
}
