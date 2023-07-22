variable azdo_organization_url {
  nullable                     = false
}
variable azdo_project_name {
  nullable                     = false
}

variable azure_resource_id {
  description                  = "The Azure scope to assign access to"
  nullable                     = false
}

variable azure_role {
  default                      = "Contributor"
  nullable                     = false
}

variable create_managed_identity {
  description                  = "Creates a Managed Identity instead of a Service Principal"
  default                      = true
  type                         = bool
}

variable managed_identity_resource_group_id {
  default                      = null
  description                  = "The resource group to create the Managed Identity in"
}

variable resource_prefix {
  description                  = "The prefix to put at the end of resource names created"
  default                      = "demo"
  nullable                     = false
}