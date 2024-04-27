# Create governed Azure Service Connection with Terraform

Many large customers have additional requirements around the Entra ID object that a service connection creates and the permissions it is assigned.

These are a few common requirements and constraints:

- Specific secret expiration and auto-rotation control
- Custom role assignments for Azure [data plane](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations) access e.g. [Key Vault](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations), [Kusto](https://learn.microsoft.com/azure/data-explorer/kusto/access-control/role-based-access-control), [Storage](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access?tabs=portal)
- Creation of app registrations is [blocked in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications) or the use of Managed Identities is explicitly mandated for Azure access
- Required ITSM metadata on Entra ID app registration (IT Service Management Reference, naming convention, notes)
- Co-owners are required to be set on Entra ID app registration
- The organization has an IT fulfillment process where identities are automatically created based on a service request

With the help of Terraform [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs), [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs) and [azuredevops](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs) providers all required changes can be performed with a single configuration.

## Terraform Configuration