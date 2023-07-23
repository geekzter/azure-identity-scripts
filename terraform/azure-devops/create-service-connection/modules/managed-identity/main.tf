data azurerm_resource_group identity {
  name                         = var.resource_group_name
}

resource azurerm_user_assigned_identity identity {
  location                     = data.azurerm_resource_group.identity.location
  name                         = var.name
  resource_group_name          = data.azurerm_resource_group.identity.name

  tags                         = var.tags
}

resource azurerm_federated_identity_credential fic {
  name                         = replace(var.federation_subject,"/[:/ ]+/","-")
  resource_group_name          = data.azurerm_resource_group.identity.name
  audience                     = ["api://AzureADTokenExchange"]
  issuer                       = var.issuer
  parent_id                    = azurerm_user_assigned_identity.identity.id
  subject                      = var.federation_subject
}