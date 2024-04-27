variable azdo_creates_identity {
  description                  = "Let Azure DevOps create identity for service connection"
  default                      = false
  type                         = bool
}

variable azdo_organization_url {
  description                  = "The Azure DevOps organization URL (e.g. https://dev.azure.com/contoso)"
  nullable                     = false
  type                         = string
}
variable azdo_project_name {
  description                  = "The Azure DevOps project name to create the service connection in"
  nullable                     = false
  type                         = string
}

variable azure_scope {
  default                      = null
  description                  = "The Azure scope to assign access to"
  type                         = string
}

variable azure_role {
  default                      = "Contributor"
  description                  = "The Azure RBAC role to assign to the service connection's identity"
  nullable                     = false
  type                         = string
}

variable azure_role_assignments {
  default                      = []
  description                  = "Additional role assignments to create for the service connection's identity"
  nullable                     = true
  type                         = set(object({scope=string, role=string}))
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
  description                  = "Object ids of the users that will be co-owners of the Entra ID app registration"
  type                         = list(string)
}

variable entra_secret_expiration_days {
  description                  = "Secret expiration in days"
  default                      = 90
  type                         = number
}

variable entra_service_management_reference {
  default                      = null
  description                  = "IT Service Management Reference to add to the App Registration"
  type                         = string
}

variable managed_identity_resource_group_id {
  default                      = null
  description                  = "The resource group to create the Managed Identity in"
  type                         = string
}

variable resource_prefix {
  description                  = "The prefix to put in front of resource names created"
  default                      = "demo"
  nullable                     = false
  type                         = string
}
variable resource_suffix {
  description                  = "The suffix to append to resource names created"
  default                      = "" # Empty string triggers a random suffix
  type                         = string
}
variable run_id {
  description                  = "The ID that identifies the pipeline / workflow that invoked Terraform (used in CI/CD)"
  default                      = null
  type                         = number
}