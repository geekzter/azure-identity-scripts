# Terraform-managed Azure Service Connection

[![Build Status](https://dev.azure.com/geekzter/Pipeline%20Playground/_apis/build/status%2Fcreate-service-connection?branchName=main&label=terraform-ci)](https://dev.azure.com/geekzter/Pipeline%20Playground/_build/latest?definitionId=5&branchName=main)

Azure DevOps uses service connections to connect to services that are targets for cloud infrastructure provisioning and application deployment. The most commonly used service connection is the [Azure Resource Manager service connection](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure?view=azure-devops). This creates an object in Azure DevOps, an identity in Entra ID and a role assignment in Azure.

Many Enterprise customers have requirements around the management of Entra [workload identities](https://learn.microsoft.com/entra/workload-id/workload-identities-overview) (applications, service principals, managed identities) as well as the permissions they are assigned to.

Here are a few common requirements and constraints:

- Creation of app registrations is [disabled in the Entra ID tenant](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications) and/or
the use of Managed Identities for Azure access is mandated
- Specific secret expiration and auto-rotation control
- ITSM metadata is required on Entra ID objects (service nanagement reference, naming convention, notes)
- Co-owners are required to exist for Entra ID apps
- Custom role assignments are needed for Azure [data plane](https://learn.microsoft.com/azure/azure-resource-manager/management/control-plane-and-data-plane#data-plane) access e.g. [Key Vault](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations), [Kusto](https://learn.microsoft.com/azure/data-explorer/kusto/access-control/role-based-access-control), [Storage](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access?tabs=portal)
- Access needs to be granted to multiple Azure subscriptions that are not part of the same management group
- An IT fulfillment process exists where identities are automatically provisioned based on a service request

## Why Terraform?

Terraform employs a provider model which enables all changes to be made by a single tool and configuration:

| Service      | Provider | API |
|--------------|----------|-----|
| Azure        | [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)     | [Azure Resource Manager REST API](https://learn.microsoft.com/rest/api/resources/) |
| Azure DevOps | [azuredevops](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs) | [Azure DevOps REST API](https://learn.microsoft.com/rest/api/azure/devops/serviceendpoint/endpoints) |
| Entra ID     | [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)     | [Microsoft Graph API](https://learn.microsoft.com/graph/use-the-api) |

[HCL](https://developer.hashicorp.com/terraform/language#about-the-terraform-language), the language used, is declarative and the tool is capable if inferring dependencies to create resources in order. This is the output from `terraform graph`:
![Terraform graph](graph.png)

More information:

- [Overview of Terraform on Azure - What is Terraform?](https://learn.microsoft.com/azure/developer/terraform/overview)
- [Cloud Adoption Framework - Infrastructure-as-Code CI/CD security guidance](https://learn.microsoft.com/azure/cloud-adoption-framework/secure/best-practices/secure-devops)

## Provisioning

Provisioning is a matter of specifying Terraform [variables](https://developer.hashicorp.com/terraform/language/values/variables) (see [inputs](#inputs) below) and running `terraform apply`. To understand how the Terraform configuration can be created in automation, review
[tf_create_azurerm_service_connection.ps1](../../../scripts/azure-devops/tf_create_azurerm_service_connection.ps1) and the
[CI pipeline](azure-pipelines.yml).  

### Examples

Terraform variable can be provided as a .auto.tfvars file, see [sample](config.auto.tfvars.sample).

#### Default configuration

This creates an App registration with Federated Identity Credential and `Contributor` role on the Azure subscription used by the Terraform `azurerm` provider.

```hcl
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
```

Pre-requisites:

- The user can create app registrations i.e.:
  - Creation of app registrations is not [disabled in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications);
  or
  - The user is member of a privileged Entra ID role e.g. [Application Developer](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#application-developer)
- The user is an owner of the Azure subscription (so role assignment can be performed)

#### Managed Identity with FIC and custom RBAC

This creates a Managed Identity with Federated Identity Credential and custom Azure RBAC (role-based access control) role assignments:

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
        role                   = "Storage Blob Data Contributor"
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

Pre-requisites:

- A resource group to hold the Managed Identity has been pre-created
- The user is an owner of the Azure scopes to create role assignments on

#### Managed Identity with FIC assigned to Entra ID security group

This creates a Managed Identity with Federated Identity Credential and custom Azure RBAC (role-based access control) role assignments:

```hcl
azdo_creates_identity          = false
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
azure_role_assignments         = []
create_federation              = true
create_managed_identity        = true
entra_security_group_names     = ["my-security-group"]
managed_identity_resource_group_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/msi-rg"
```

Pre-requisites:

- A resource group to hold the Managed Identity has been pre-created
- The user is an owner of the security enabled Entra ID group to add the Managed Identity to

#### App registration with FIC and ITSM metadata

This creates an Entra ID app registration with IT service reference and notes fields populated as well as specifying co-owners:

```hcl
azdo_creates_identity          = false
azdo_organization_url          = "https://dev.azure.com/my-organization"
azdo_project_name              = "my-project"
create_federation              = true
create_managed_identity        = false
entra_app_notes                = "Service connection for business application ABC deployment to XYZ environment"
entra_app_owner_object_ids     = ["00000000-0000-0000-0000-000000000000","11111111-1111-1111-1111-111111111111"]
entra_service_management_reference = "11111111-1111-1111-1111-111111111111"
```

Pre-requisites:

- The user can create app registrations i.e.:
  - Creation of app registrations is not [disabled in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications);
  or
  - The user is member of a privileged Entra ID role e.g. [Application Developer](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#application-developer)
- The user is an owner of the Azure subscription (so role assignment can be performed)

#### App registration with short-lived secret and constrained RBAC

This creates an Entra ID app registration with secret that expires after 1 hour:

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
Pre-requisites:

- The user can create app registrations i.e.:
  - Creation of app registrations is not [disabled in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications);
  or
  - The user is member of a privileged Entra ID role e.g. [Application Developer](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#application-developer)
- The user is an owner of the Azure resource group (so role assignment can be performed)

## Terraform Configuration

The (required) variables and output are listed below. Sensitive outputs are masked by default.
Generated with [terraform-docs](https://terraform-docs.io/).
