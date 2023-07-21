output application_id {
  value       = azuread_application.app_registration.application_id
}
output application_url {
  description = "This is the URL to the Azure Portal Application Registration page for this application."
  value       = "https://portal.azure.com/${data.azuread_client_config.current.tenant_id}/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/quickStartType~/null/sourceType/Microsoft_AAD_IAM/appId/${azuread_application.app_registration.application_id}/objectId/${azuread_application.app_registration.id}/isMSAApp~/false/defaultBlade/Overview/appSignInAudience/AzureADMyOrg/servicePrincipalCreated~/true"
}
output object_id {
  value       = azuread_application.app_registration.id
}
output principal_id {
  value       = azuread_service_principal.spn.object_id
}
output principal_url {
  description = "This is the URL to the Azure Portal Enterprise (Service Principal) Application page for this application."
  value       = "https://portal.azure.com/${data.azuread_client_config.current.tenant_id}/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/${azuread_service_principal.spn.id}/appId/${azuread_application.app_registration.application_id}/preferredSingleSignOnMode~/null"

}
