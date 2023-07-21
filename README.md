# Azure Identity Scripts

[![azure-cli-ci](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml)

This repo contains a few [PowerShell](https://github.com/PowerShell/PowerShell) scripts that use the [Azure CLI](https://github.com/Azure/azure-cli) to create or find Azure Active Directory objects:

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
- List identities for Azure Pipeline Service Connections by Azure DevOps organization and (optionally) project: [list_service_connections.ps1](scripts/list_service_connections.ps1)
- Purge deleted directory objects (e.g. applications) [purge_deleted_objects.ps1](scripts/purge_deleted_objects.ps1)
- Create Service Principal for GitHub Actions with Workload identity federation: [create_sp_for_github_actions.ps1](scripts/github/github-actions.md)   
