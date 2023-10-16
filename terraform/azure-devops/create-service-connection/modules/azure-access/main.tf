data azurerm_subscription target {
    subscription_id            = split("/", var.resource_id)[2]
}

resource azurerm_role_assignment resouce_access {
  scope                        = var.resource_id
  role_definition_name         = var.role
  principal_id                 = var.identity_object_id

  count                        = var.create_role_assignment ? 1 : 0
}