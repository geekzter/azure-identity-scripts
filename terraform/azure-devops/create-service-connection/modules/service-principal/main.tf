data azuread_client_config current {}

locals {
  owner_object_id              = var.owner_object_id != null && var.owner_object_id != "" ? lower(var.owner_object_id) : data.azuread_client_config.current.object_id
  expiration_expression        = "${var.secret_expiration_days * 24}h01m"
}

resource azuread_application app_registration {
  display_name                 = var.name
  owners                       = [local.owner_object_id]
  service_management_reference = var.service_management_reference
  sign_in_audience             = var.multi_tenant ? "AzureADMultipleOrgs" : null
}

resource azuread_service_principal spn {
  application_id               = azuread_application.app_registration.client_id
  owners                       = [local.owner_object_id]
}

resource azuread_application_federated_identity_credential fic {
  application_object_id        = azuread_application.app_registration.object_id
  description                  = "Created by Terraform"
  display_name                 = replace(var.federation_subject,"/[:/ ]+/","-")
  audiences                    = ["api://AzureADTokenExchange"]
  issuer                       = var.issuer
  subject                      = var.federation_subject

  count                        = var.create_federation ? 1 : 0
}

resource time_rotating secret_expiration {
  rotation_days                = max(var.secret_expiration_days,1)

  count                        = var.create_federation ? 0 : 1
}
resource azuread_application_password secret {
  end_date_relative            = local.expiration_expression
  rotate_when_changed          = {
    rotation                   = timeadd(time_rotating.secret_expiration.0.id, local.expiration_expression)
  }

  application_object_id        = azuread_application.app_registration.id

  count                        = var.create_federation ? 0 : 1
}