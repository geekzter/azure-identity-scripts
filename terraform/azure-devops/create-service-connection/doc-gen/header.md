# Terraform-managed Azure Service Connection

[![Build Status](https://dev.azure.com/geekzter/Pipeline%20Playground/_apis/build/status%2Fcreate-service-connection?branchName=main&label=terraform-ci)](https://dev.azure.com/geekzter/Pipeline%20Playground/_build/latest?definitionId=5&branchName=main)

Many large customers have additional requirements around the management of the Entra ID object that a service connection creates and the permissions it is assigned to.

These are a few common requirements and constraints:

- Specific secret expiration and auto-rotation control
- Custom role assignments for Azure [data plane](https://learn.microsoft.com/azure/azure-resource-manager/management/control-plane-and-data-plane#data-plane) access e.g. [Key Vault](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations), [Kusto](https://learn.microsoft.com/azure/data-explorer/kusto/access-control/role-based-access-control), [Storage](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access?tabs=portal)
- Creation of app registrations is [disabled in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications) or the use of Managed Identities for Azure access is explicitly mandated
- Required ITSM metadata on Entra ID app registration (IT Service Management Reference, naming convention, notes)
- Co-owners are required to exist for Entra ID app registrations
- The organization has an IT fulfillment process where identities are automatically created based on a service request

## Why Terraform?

Terraform employs a provider model which enable all changes to be made by a single tool and configuration:

| Service      | Provider | API |
|--------------|----------|-----|
| Azure        | [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)     | [Azure Resource Manager REST API](https://learn.microsoft.com/rest/api/resources/) |
| Azure DevOps | [azuredevops](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs) | [Azure DevOps REST API](https://learn.microsoft.com/rest/api/azure/devops/serviceendpoint/endpoints) |
| Entra ID     | [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)     | [Microsoft Graph API](https://learn.microsoft.com/graph/use-the-api) |

Terraform is a declarative tool that is capable if inferring dependencies to create resources in the correct order. This is the output from `terraform graph`:
![Terraform graph](graph.png)

More information:

- [Overview of Terraform on Azure - What is Terraform?](https://learn.microsoft.com/azure/developer/terraform/overview)
- [Cloud Adoption Framework Infrastructure-as-Code CI/CD security guidance](https://learn.microsoft.com/azure/cloud-adoption-framework/secure/best-practices/secure-devops)

## Provisioning

Provisioning is a matter of specifying [variables](https://developer.hashicorp.com/terraform/language/values/variables) (see [inputs](#input_azdo_organization_url) below) and running `terraform apply`. To understand how the Terraform configuration can be created in automation, review
[tf_create_azurerm_service_connection.ps1](../../../scripts/azure-devops/tf_create_azurerm_service_connection.ps1) and the
[CI pipeline](azure-pipelines.yml).  

### Examples

Terraform variable can be provided as a .auto.tfvars file, see [sample](config.auto.tfvars.sample).

#### App registration with Federated Credential and ITSM data

```hcl
azdo_creates_identity          = false
azure_role_assignments         = [
    {
        scope                  = "/subscriptions/00000000-0000-0000-0000-000000000000" 
        role                   = "Contributor"
    },
    {
        scope                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg" 
        role                   = "Storage Blob Data Contributor"
    }
]
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
create_federation              = true
create_managed_identity        = false
entra_owner_object_ids         = ["00000000-0000-0000-0000-000000000000","11111111-1111-1111-1111-111111111111"]
entra_service_management_reference = "11111111-1111-1111-1111-111111111111"
```

#### App registration with short-lived secret

```hcl
azdo_creates_identity          = false
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
azure_role_assignments         = [
    {
        scope                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg"
        role                   = "Reader"
    }
]
create_federation              = false
create_managed_identity        = false
entra_secret_expiration_days   = 0 # secret lasts 1 hour
```

#### Managed Identity with Federated Credential

```hcl
azdo_creates_identity          = false
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
azure_role_assignments         = [
    {
        scope                  = "/subscriptions/00000000-0000-0000-0000-000000000000" 
        role                   = "Contributor"
    },
    {
        scope                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg" 
        role                   = "Key Vault Secrets User"
    }
]
create_federation              = true
create_managed_identity        = true
managed_identity_resource_group_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/msi-rg"
```

## Terraform Configuration

Generated with [terraform-docs](https://terraform-docs.io/)