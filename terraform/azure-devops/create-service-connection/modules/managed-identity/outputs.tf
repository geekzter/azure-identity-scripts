output application_id {
  value       = azurerm_user_assigned_identity.identity.client_id
}
output identity_url {
  value       = "https://portal.azure.com/#@${azurerm_user_assigned_identity.identity.tenant_id}/resource${azurerm_user_assigned_identity.identity.id}"
}
output principal_id {
  value       = azurerm_user_assigned_identity.identity.principal_id
}
output principal_name {
  value       = azurerm_user_assigned_identity.identity.name
}
output principal_url {
  value       = "https://portal.azure.com/${azurerm_user_assigned_identity.identity.tenant_id}/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/${azurerm_user_assigned_identity.identity.principal_id}/appId/${azurerm_user_assigned_identity.identity.client_id}"
}
output tenant_id {
  value       = azurerm_user_assigned_identity.identity.tenant_id
}