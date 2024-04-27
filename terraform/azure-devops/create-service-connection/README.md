<!-- BEGIN_TF_DOCS -->
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

#### Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider_azurerm) | 3.99.0 |
| <a name="provider_external"></a> [external](#provider_external) | 2.3.3 |
| <a name="provider_random"></a> [random](#provider_random) | 3.6.0 |
| <a name="provider_terraform"></a> [terraform](#provider_terraform) | n/a |

#### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_azure_access"></a> [azure_access](#module_azure_access) | ./modules/azure-access | n/a |
| <a name="module_azure_role_assignments"></a> [azure_role_assignments](#module_azure_role_assignments) | ./modules/azure-access | n/a |
| <a name="module_entra_app"></a> [entra_app](#module_entra_app) | ./modules/app-registration | n/a |
| <a name="module_managed_identity"></a> [managed_identity](#module_managed_identity) | ./modules/managed-identity | n/a |
| <a name="module_service_connection"></a> [service_connection](#module_service_connection) | ./modules/service-connection | n/a |

#### Inputs

| Name | Description | Type |
|------|-------------|------|
| <a name="input_azdo_organization_url"></a> [azdo_organization_url](#input_azdo_organization_url) | The Azure DevOps organization URL (e.g. https://dev.azure.com/contoso) | `string` |
| <a name="input_azdo_project_name"></a> [azdo_project_name](#input_azdo_project_name) | The Azure DevOps project name to create the service connection in | `string` |
| <a name="input_azdo_creates_identity"></a> [azdo_creates_identity](#input_azdo_creates_identity) | Let Azure DevOps create identity for service connection | `bool` |
| <a name="input_azure_role"></a> [azure_role](#input_azure_role) | The Azure RBAC role to assign to the service connection's identity | `string` |
| <a name="input_azure_role_assignments"></a> [azure_role_assignments](#input_azure_role_assignments) | Additional role assignments to create for the service connection's identity | `set(object({scope=string, role=string}))` |
| <a name="input_azure_scope"></a> [azure_scope](#input_azure_scope) | The Azure scope to assign access to | `string` |
| <a name="input_create_federation"></a> [create_federation](#input_create_federation) | Use workload identity federation instead of a App Registration secret | `bool` |
| <a name="input_create_managed_identity"></a> [create_managed_identity](#input_create_managed_identity) | Creates a Managed Identity instead of a App Registration | `bool` |
| <a name="input_entra_owner_object_ids"></a> [entra_owner_object_ids](#input_entra_owner_object_ids) | Object ids of the users that will be co-owners of the Entra ID app registration | `list(string)` |
| <a name="input_entra_secret_expiration_days"></a> [entra_secret_expiration_days](#input_entra_secret_expiration_days) | Secret expiration in days | `number` |
| <a name="input_entra_service_management_reference"></a> [entra_service_management_reference](#input_entra_service_management_reference) | IT Service Management Reference to add to the App Registration | `string` |
| <a name="input_managed_identity_resource_group_id"></a> [managed_identity_resource_group_id](#input_managed_identity_resource_group_id) | The resource group to create the Managed Identity in | `string` |
| <a name="input_resource_prefix"></a> [resource_prefix](#input_resource_prefix) | The prefix to put in front of resource names created | `string` |
| <a name="input_resource_suffix"></a> [resource_suffix](#input_resource_suffix) | The suffix to append to resource names created | `string` |
| <a name="input_run_id"></a> [run_id](#input_run_id) | The ID that identifies the pipeline / workflow that invoked Terraform (used in CI/CD) | `number` |

#### Outputs

| Name | Description |
|------|-------------|
| <a name="output_azdo_project_id"></a> [azdo_project_id](#output_azdo_project_id) | The Azure DevOps project id the service connection was created in |
| <a name="output_azdo_service_connection_id"></a> [azdo_service_connection_id](#output_azdo_service_connection_id) | The Azure DevOps service connection id |
| <a name="output_azdo_service_connection_name"></a> [azdo_service_connection_name](#output_azdo_service_connection_name) | The Azure DevOps service connection name |
| <a name="output_azdo_service_connection_url"></a> [azdo_service_connection_url](#output_azdo_service_connection_url) | The Azure DevOps service connection portal URL |
| <a name="output_azure_resource_group_name"></a> [azure_resource_group_name](#output_azure_resource_group_name) | The name of the resource group the service connection was granted access to |
| <a name="output_azure_scope"></a> [azure_scope](#output_azure_scope) | The Azure scope the service connection was granted access to |
| <a name="output_azure_scope_url"></a> [azure_scope_url](#output_azure_scope_url) | The Azure scope portal URL the service connection was granted access to |
| <a name="output_azure_subscription_id"></a> [azure_subscription_id](#output_azure_subscription_id) | The Azure subscription id the service connection was granted access to |
| <a name="output_azure_subscription_name"></a> [azure_subscription_name](#output_azure_subscription_name) | The Azure subscription name the service connection was granted access to |
| <a name="output_identity_application_id"></a> [identity_application_id](#output_identity_application_id) | The app/client id of the service connection's identity |
| <a name="output_identity_application_name"></a> [identity_application_name](#output_identity_application_name) | The name of the service connection's identity |
| <a name="output_identity_federation_subject"></a> [identity_federation_subject](#output_identity_federation_subject) | The federation subject |
| <a name="output_identity_issuer"></a> [identity_issuer](#output_identity_issuer) | The federation issuer |
| <a name="output_identity_object_id"></a> [identity_object_id](#output_identity_object_id) | The object id of the service connection's identity |
| <a name="output_identity_principal_id"></a> [identity_principal_id](#output_identity_principal_id) | The service principal id of the service connection's identity |
| <a name="output_identity_principal_name"></a> [identity_principal_name](#output_identity_principal_name) | The service principal name of the service connection's identity |
| <a name="output_identity_principal_url"></a> [identity_principal_url](#output_identity_principal_url) | The service principal portal url of the service connection's identity |
| <a name="output_identity_secret"></a> [identity_secret](#output_identity_secret) | The secret of the service connection's identity |
| <a name="output_identity_secret_end_date"></a> [identity_secret_end_date](#output_identity_secret_end_date) | The secret expiration date of the service connection's identity |
| <a name="output_identity_url"></a> [identity_url](#output_identity_url) | The portal url of the service connection's identity |
<!-- END_TF_DOCS -->