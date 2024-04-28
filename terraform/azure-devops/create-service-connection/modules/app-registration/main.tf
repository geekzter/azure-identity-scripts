data azuread_client_config current {}

locals {
  owner_object_ids              = var.owner_object_ids != null ? var.owner_object_ids : [data.azuread_client_config.current.object_id]
  expiration_expression        = "${(var.secret_expiration_days * 24) + 1}h01m"
}

resource azuread_application app_registration {
  display_name                 = var.name
  notes                        = var.notes
  owners                       = local.owner_object_ids
  prevent_duplicate_names      = true
  service_management_reference = var.service_management_reference
  sign_in_audience             = var.multi_tenant ? "AzureADMultipleOrgs" : null
}

resource azuread_service_principal spn {
  client_id                    = azuread_application.app_registration.client_id
  notes                        = var.notes
  owners                       = local.owner_object_ids
}

resource azuread_application_federated_identity_credential fic {
  application_id               = azuread_application.app_registration.id
  description                  = var.notes
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

  application_id               = azuread_application.app_registration.id

  count                        = var.create_federation ? 0 : 1
}