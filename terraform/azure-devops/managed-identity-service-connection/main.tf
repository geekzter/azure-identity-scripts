data azuread_client_config current {}

# Random resource suffix, this will prevent name collisions when creating resources in parallel
resource random_string suffix {
  length                       = 4
  upper                        = false
  lower                        = true
  numeric                      = false
  special                      = false
}

locals {
  azdo_organization_url        = replace(var.azdo_organization_url,"/\\/$/","")
  azdo_organization_name       = replace(var.azdo_organization_url,"/.*dev.azure.com//","")
  azdo_service_connection_name = "msi-oidc-${terraform.workspace}-${local.suffix}"
  owner_object_id              = var.owner_object_id != null && var.owner_object_id != "" ? lower(var.owner_object_id) : data.azuread_client_config.current.object_id
  suffix                       = random_string.suffix.result
}

module service_principal {
  source                       = "./modules/service-principal"
  federation_subject           = "sc://${local.azdo_organization_name}/${var.azdo_project_name}/${local.azdo_service_connection_name}"
  issuer                       = "https://app.vstoken.visualstudio.com"
  name                         = "${var.resource_prefix}-azure-service-connection-${terraform.workspace}-${local.suffix}"
  owner_object_id              = local.owner_object_id
}