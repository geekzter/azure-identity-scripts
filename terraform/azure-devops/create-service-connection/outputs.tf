output azdo_project_id {
  description = "The Azure DevOps project id the service connection was created in"
  value       = module.service_connection.project_id
}
output azdo_service_connection_id {
  description = "The Azure DevOps service connection id"
  value       = module.service_connection.service_connection_id
}
output azdo_service_connection_name {
  description = "The Azure DevOps service connection name"
  value       = local.azdo_service_connection_name
}
output azdo_service_connection_url {
  description = "The Azure DevOps service connection portal URL"
  value       = module.service_connection.service_connection_url
}
output azure_resource_group_name {
  description = "The name of the resource group the service connection was granted access to"
  value       = try(split("/", local.azure_scope)[4],null)
}
output azure_scope {
  description = "The Azure scope the service connection was granted access to"
  value       = local.azure_scope
}
output azure_scope_url {
  description = "The Azure scope portal URL the service connection was granted access to"
  value       = module.azure_access.resource_url
}
output azure_subscription_id {
  description = "The Azure subscription id the service connection was granted access to"
  value       = local.target_subscription_id
}
output azure_subscription_name {
  description = "The Azure subscription name the service connection was granted access to"
  value       = module.azure_access.subscription_name
}

output identity_application_id {
  description = "The app/client id of the service connection's identity"
  value       = local.application_id
}
output identity_application_name {
  description = "The name of the service connection's identity"
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.entra_app.0.application_name
}
output identity_federation_subject {
  description = "The federation subject"
  value       = module.service_connection.service_connection_oidc_subject
}
output identity_issuer {
  description = "The federation issuer"
  value       = module.service_connection.service_connection_oidc_issuer
}
output identity_object_id {
  description = "The object id of the service connection's identity"
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.entra_app.0.object_id
}
output identity_principal_id {
  description = "The service principal id of the service connection's identity"
  value       = local.principal_id
}
output identity_principal_name {
  description = "The service principal name of the service connection's identity"
  value       = local.principal_name
}
output identity_principal_url {
  description = "The service principal portal url of the service connection's identity"
  value       = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.principal_url : module.entra_app.0.principal_url)
}
output identity_secret {
  description = "The secret of the service connection's identity"
  sensitive   = true
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.entra_app.0.secret
}
output identity_secret_end_date {
  description = "The secret expiration date of the service connection's identity"
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.entra_app.0.secret_end_date
}
output identity_url {
  description = "The portal url of the service connection's identity"
  value       = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.identity_url : module.entra_app.0.application_url)
}