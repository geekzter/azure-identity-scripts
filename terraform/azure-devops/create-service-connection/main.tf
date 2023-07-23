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
  application_id               = var.create_managed_identity ? module.managed_identity.0.application_id : module.service_principal.0.application_id
  azdo_organization_name       = replace(var.azdo_organization_url,"/.*dev.azure.com//","")
  azdo_organization_url        = replace(var.azdo_organization_url,"/\\/$/","")
  azdo_service_connection_name = "${replace(module.azure_access.subscription_name,"/ +/","-")}-oidc-${var.create_managed_identity ? "msi" : "sp"}${terraform.workspace == "default" ? "" : format("-%s",terraform.workspace)}-${local.resource_suffix}"
  azure_scope                  = var.azure_scope != null && var.azure_scope != "" ? var.azure_scope : "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  federation_subject           = "sc://${local.azdo_organization_name}/${var.azdo_project_name}/${local.azdo_service_connection_name}"
  principal_id                 = var.create_managed_identity ? module.managed_identity.0.principal_id : module.service_principal.0.principal_id
  principal_name               = var.create_managed_identity ? module.managed_identity.0.principal_name : module.service_principal.0.principal_name
  issuer                       = "https://app.vstoken.visualstudio.com"
  # issuer                       = "https://vstoken.dev.azure.com/${local.azdo_organization_id}"
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
  managed_identity_subscription_id = split("/", var.managed_identity_resource_group_id)[2]
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
}

module managed_identity {
  providers                    = {
    azurerm                    = azurerm.managed_identity
  }
  source                       = "./modules/managed-identity"
  federation_subject           = local.federation_subject
  issuer                       = local.issuer
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.resource_suffix}"
  resource_group_name          = split("/", var.managed_identity_resource_group_id)[4]
  tags                         = local.resource_tags

  count                        = var.create_managed_identity ? 1 : 0
  depends_on                   = [terraform_data.managed_identity_validator]
}

module service_principal {
  source                       = "./modules/service-principal"
  federation_subject           = local.federation_subject
  issuer                       = local.issuer
  multi_tenant                 = false
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.resource_suffix}"

  count                        = var.create_managed_identity ? 0 : 1
}

module azure_access {
  providers                    = {
    azurerm                    = azurerm.target
  }
  source                       = "./modules/azure-access"
  identity_object_id           = local.principal_id
  resource_id                  = local.azure_scope
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
