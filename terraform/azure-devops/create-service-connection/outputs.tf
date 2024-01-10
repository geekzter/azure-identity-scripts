output azdo_project_id {
  value       = module.service_connection.project_id
}
output azdo_service_connection_id {
  value       = module.service_connection.service_connection_id
}
output azdo_service_connection_name {
  value       = local.azdo_service_connection_name
}
output azdo_service_connection_url {
  value       = module.service_connection.service_connection_url
}
output azure_resource_group_name {
  value       = try(split("/", local.azure_scope)[4],null)
}
output azure_scope {
  value       = local.azure_scope
}
output azure_scope_url {
  value       = module.azure_access.resource_url
}
output azure_subscription_id {
  value       = local.target_subscription_id
}
output azure_subscription_name {
  value       = module.azure_access.subscription_name
}

output identity_application_id {
  value       = local.application_id
}
output identity_application_name {
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.service_principal.0.application_name
}
output identity_federation_subject {
  value       = module.service_connection.service_connection_oidc_subject
}
output identity_issuer {
  value       = module.service_connection.service_connection_oidc_issuer
}
output identity_object_id {
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.service_principal.0.object_id
}
output identity_principal_id {
  value       = local.principal_id
}
output identity_principal_name {
  value       = local.principal_name
}
output identity_principal_url {
  value       = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.principal_url : module.service_principal.0.principal_url)
}
output identity_secret {
  sensitive   = true
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.service_principal.0.secret
}
output identity_secret_end_date {
  value       = var.azdo_creates_identity || var.create_managed_identity ? null : module.service_principal.0.secret_end_date
}
output identity_url {
  value       = var.azdo_creates_identity ? null : (var.create_managed_identity ? module.managed_identity.0.identity_url : module.service_principal.0.application_url)
}

