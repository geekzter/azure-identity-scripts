data azuredevops_client_config current {}

data azuredevops_project project {
  name                         = var.project_name
}

resource azuredevops_serviceendpoint_azurerm azurerm {
  project_id                   = data.azuredevops_project.project.id
  service_endpoint_name        = var.service_connection_name
  description                  = "Managed by Terraform"
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"
  credentials {
    serviceprincipalid         = var.application_id
  }
  azurerm_spn_tenantid         = var.tenant_id
  azurerm_subscription_id      = var.subscription_id
  azurerm_subscription_name    = var.subscription_name
}
