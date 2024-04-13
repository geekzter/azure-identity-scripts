variable azdo_creates_identity {
  description                  = "Let Azure DevOps create App Registration"
  default                      = false
  type                         = bool
}
variable azdo_organization_id {
  default                      = null
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

variable create_federation {
  description                  = "Use workload identity federation instead of a App Registration secret"
  default                      = true
  type                         = bool
}

variable create_managed_identity {
  description                  = "Creates a Managed Identity instead of a App Registration"
  default                      = true
  type                         = bool
}

variable entra_owner_object_ids {
  default                      = null
  description                  = "The object ids of the users that will be owners of the Entra ID app registration"
  type                         = list(string)
}

variable entra_secret_expiration_days {
  description                  = "Secret expiration in days"
  default                      = 90
  type                         = number
}

variable entra_service_management_reference {
  description                  = "IT Service Management Reference"
  default                      = null
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