output application_id {
  value       = local.application_id
}
output application_name {
  value       = var.create_managed_identity ? null : module.service_principal.0.application_name
}
output azdo_token {
  sensitive   = true
  value       = data.external.azdo_token.result.accessToken
}
output federation_subject {
  value       = local.federation_subject
}
output identity_url {
  value       = var.create_managed_identity ? module.managed_identity.0.identity_url : module.service_principal.0.application_url
}
output issuer {
  value       = local.issuer
}
output object_id {
  value       = var.create_managed_identity ? null : module.service_principal.0.object_id
}
output principal_id {
  value       = local.principal_id
}
output principal_name {
  value       = local.principal_name
}
output principal_url {
  value       = var.create_managed_identity ? module.managed_identity.0.principal_url : module.service_principal.0.principal_url
}

output subscription_name {
  value       = module.azure_access.subscription_name
}
