# Terraform governed Azure Service Connection

Many large customers have additional requirements around the Entra ID object that a service connection creates and the permissions it is assigned.

These are a few common requirements and constraints:

- Specific secret expiration and auto-rotation control
- Custom role assignments for Azure [data plane](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations) access e.g. [Key Vault](https://learn.microsoft.com/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations), [Kusto](https://learn.microsoft.com/azure/data-explorer/kusto/access-control/role-based-access-control), [Storage](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access?tabs=portal)
- Creation of app registrations is [blocked in Entra ID](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications) or the use of Managed Identities is explicitly mandated for Azure access
- Required ITSM metadata on Entra ID app registration (IT Service Management Reference, naming convention, notes)
- Co-owners are required to be set on Entra ID app registration
- The organization has an IT fulfillment process where identities are automatically created based on a service request

Terraform employs a provider model which enable all changes to be made by a single tool and configuration:

| Service      | Provider | API |
|--------------|----------|-----|
| Azure        | [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)     | [Azure Resource Manager REST API](https://learn.microsoft.com/rest/api/resources/) |
| Azure DevOps | [azuredevops](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs) | [Azure DevOps REST API](https://learn.microsoft.com/rest/api/azure/devops/serviceendpoint/endpoints) |
| Entra ID     | [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)     | [Microsoft Graph API](https://learn.microsoft.com/graph/use-the-api) |


## Provisioning

Terraform is a declarative tool that is capable if inferring dependencies to create resources in the correct order. This is the output from `terraform graph`:
![Terraform graph](graph.png)

Provisioning is a matter of specifying [variables](https://developer.hashicorp.com/terraform/language/values/variables) (see [inputs](#input_azdo_organization_url) below) running `terraform apply`. 

- To understand how the Terraform configuration can be created in automation, review
[tf_create_azurerm_service_connection.ps1](../../../scripts/azure-devops/tf_create_azurerm_service_connection.ps1) and the
[CI pipeline](azure-pipelines.yml).  
- For more information on using Terraform with Azure and other Microsoft services, see [Overview of Terraform on Azure - What is Terraform?](https://learn.microsoft.com/azure/developer/terraform/overview)
- For infrastructure-as-code best practices, review [Securing the pipeline and CI/CD workflow](https://learn.microsoft.com/azure/cloud-adoption-framework/secure/best-practices/secure-devops).


## Terraform Configuration