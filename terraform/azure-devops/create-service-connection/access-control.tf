module azure_role_assignments {
  providers                    = {
    azurerm                    = azurerm.target
  }
  source                       = "./modules/azure-access"
  create_role_assignment       = !var.azdo_creates_identity
  identity_object_id           = local.principal_id
  resource_id                  = each.value.scope
  role                         = each.value.role

  for_each                     = { for ra in local.azure_role_assignments : format("%s-%s", ra.scope, ra.role) => ra }
}

data azuread_group entra_security_group {
  display_name                 = each.value
  for_each                     = toset(var.entra_security_group_names)

  lifecycle {
    postcondition {
      condition                = self.security_enabled
      error_message            = "${self.display_name} is not a security enabled"
    }
    postcondition {
      condition                = !self.onpremises_sync_enabled || self.writeback_enabled 
      error_message            = "${self.display_name} is a synced group that is not writeback enabled"
    }
  }
}

resource azuread_group_member entra_security_group {
  group_object_id              = each.value.object_id 
  member_object_id             = local.principal_id

  for_each                     = data.azuread_group.entra_security_group
}