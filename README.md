# Azure Identity Scripts

[![github-secrets-ci](https://github.com/geekzter/azure-identity-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/geekzter/azure-identity-scripts/actions/workflows/ci.yml)
[![Build Status](https://dev.azure.com/geekzter/Pipeline%20Playground/_apis/build/status%2Fcreate-service-connection?branchName=refs%2Fpull%2F18%2Fmerge&label=create-service-connection)](https://dev.azure.com/geekzter/Pipeline%20Playground/_build/latest?definitionId=5&branchName=refs%2Fpull%2F18%2Fmerge)

This repo contains a few [PowerShell](https://github.com/PowerShell/PowerShell) scripts that use the [Azure CLI](https://github.com/Azure/azure-cli) to create or find Azure Active Directory objects:

## Azure Active Directory

- Find Service Principal or Managed Identity with [find_workload_identity.ps1](scripts/find_workload_identity.ps1), using any of these as argument:
  - Application/Client id
  - Object/Principal id
  - (Display) Name
  - Service Principal Name
  - Resource id of a resource with a System-assigned Identity
  - Resource id or name of a User-assigned Identity
- Use Microsoft Graph to list Managed Identities with [list_managed_identities.ps1](scripts/list_managed_identities.ps1), using:
  - Azure subscription and optional resource group
  - Name (pattern)
- Purge deleted directory objects (e.g. applications) [purge_deleted_objects.ps1](scripts/purge_deleted_objects.ps1)

## Azure DevOps

- Configure Terraform [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs#authenticating-to-azure-active-directory)/[azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure) provider `ARM_*` environment variables to use the [AzureCLI](https://learn.microsoft.com/azure/devops/pipelines/tasks/reference/azure-cli-v2?view=azure-pipelines) task [Service Connection](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure?view=azure-devops):  
  [set_terraform_azurerm_vars.ps1](scripts/azure-devops/set_terraform_azurerm_vars.ps1)
- Create Managed Identity for Service Connection with Workload identity federation: [create_azurerm_msi_oidc_service_connection.ps1](scripts/azure-devops/create_azurerm_msi_oidc_service_connection.ps1)
- Create Managed Identity for Service Connection with Workload identity federation with [Terraform](terraform/azure-devops/create-service-connection)
- List identities for Azure Pipeline Service Connections in Azure Active Directory pertaining to Azure DevOps organization and (optionally) project: [list_service_connections.ps1](scripts/azure-devops/list_service_connections.ps1)

## GitHub

- Create Service Principal for GitHub Actions with Workload identity federation: [create_sp_for_github_actions.ps1](scripts/github/github-actions.md)   
