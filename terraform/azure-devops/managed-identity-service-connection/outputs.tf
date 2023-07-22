output azdo_project_id {
  value       = module.service_connection.project_id
}
output azdo_service_connection_name {
  value       = local.azdo_service_connection_name
}

output azure_resource_group_name {
  value       = split("/", var.azure_resource_id)[4]
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
  value       = var.create_managed_identity ? null : module.service_principal.0.application_name
}
output identity_federation_subject {
  value       = local.federation_subject
}
output identity_issuer {
  value       = local.issuer
}
output identity_object_id {
  value       = var.create_managed_identity ? null : module.service_principal.0.object_id
}
output identity_principal_id {
  value       = local.principal_id
}
output identity_principal_name {
  value       = local.principal_name
}
output identity_principal_url {
  value       = var.create_managed_identity ? module.managed_identity.0.principal_url : module.service_principal.0.principal_url
}
output identity_url {
  value       = var.create_managed_identity ? module.managed_identity.0.identity_url : module.service_principal.0.application_url
}

