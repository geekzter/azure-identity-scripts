data azuread_client_config current {}

locals {
  owner_object_id              = var.owner_object_id != null && var.owner_object_id != "" ? lower(var.owner_object_id) : data.azuread_client_config.current.object_id
}

resource azuread_application app_registration {
  display_name                 = var.name
  owners                       = [local.owner_object_id]
}

resource azuread_service_principal spn {
  application_id               = azuread_application.app_registration.application_id
  owners                       = [local.owner_object_id]
}

resource azuread_application_federated_identity_credential fic {
  application_object_id        = azuread_application.app_registration.object_id
  description                  = "Created by Terraform"
  display_name                 = replace(var.federation_subject,"/[:/]+/","-")
  audiences                    = ["api://AzureADTokenExchange"]
  issuer                       = var.issuer
  subject                      = var.federation_subject
}