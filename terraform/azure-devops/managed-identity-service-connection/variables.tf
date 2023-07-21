variable azdo_organization_url {
  nullable                     = false
}
variable azdo_project_name {
  nullable                     = false
}
variable owner_object_id {
  default                      = null
}
variable resource_prefix {
  description                  = "The prefix to put at the end of resource names created"
  default                      = "demo"
  nullable                     = false
}