output project_id {
  value       = data.azuredevops_project.project.project_id
}
output service_connection_id {
  value       = azuredevops_serviceendpoint_azurerm.azurerm.id
}
output service_connection_url {
  value       = "${data.azuredevops_client_config.current.organization_url}/${var.project_name}/_settings/adminservices?resourceId=${azuredevops_serviceendpoint_azurerm.azurerm.id}"
}