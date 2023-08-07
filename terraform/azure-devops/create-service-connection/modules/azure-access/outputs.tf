output resource_url {
  value       = "https://portal.azure.com/#@${data.azurerm_subscription.target.tenant_id}/resource${var.resource_id}"
}
output subscription_name {
  value       = data.azurerm_subscription.target.display_name
}
