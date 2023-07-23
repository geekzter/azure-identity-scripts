variable azdo_organization_id {
  nullable                     = true
}
variable azdo_organization_url {
  nullable                     = false
}
variable azdo_project_name {
  nullable                     = false
}

variable azure_scope {
  description                  = "The Azure scope to assign access to"
  default                      = null
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
variable resource_suffix {
  description                  = "The suffix to put at the of resource names created"
  default                      = "" # Empty string triggers a random suffix
}
variable run_id {
  description                  = "The ID that identifies the pipeline / workflow that invoked Terraform"
  default                      = null
}