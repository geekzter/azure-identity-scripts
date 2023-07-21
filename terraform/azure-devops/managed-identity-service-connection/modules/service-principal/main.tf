data azuread_client_config current {}

resource azuread_application app_registration {
  display_name                 = var.name
  owners                       = [var.owner_object_id]
}

resource azuread_service_principal spn {
  application_id               = azuread_application.app_registration.application_id
  owners                       = [var.owner_object_id]
}

resource azuread_application_federated_identity_credential fic {
  application_object_id        = azuread_application.app_registration.object_id
  description                  = "Created by Terraform"
  display_name                 = replace(var.federation_subject,"/[:/]+/","-")
  audiences                    = ["api://AzureADTokenExchange"]
  issuer                       = var.issuer
  subject                      = var.federation_subject
}