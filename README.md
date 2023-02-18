# Azure Active Directory Scripts

[![azure-cli-ci](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml)

This repo contains a few [PowerShell](https://github.com/PowerShell/PowerShell) scripts that use the [Azure CLI](https://github.com/Azure/azure-cli) to create or find Azure Active Directory objects:

- Find Service Principal or Managed Identity with [find_workload_identity.ps1](scripts/find_workload_identity.ps1), using any of these as argument:
  - Application/Client id
  - Object/Principal id
  - (Display) Name
  - Service Principal Name
  - Resource ID of a resource with a System-assigned Identity
  - Resource ID or name of a User-assigned Identity
- List Managed Identities using Microsoft Graph and Azure Resource Graph with [find_managed_identities.ps1](scripts/find_managed_identities.ps1)
- Create Service Principal for GitHub Actions with Workload Identity (OpenID Connect) pattern: [create_sp_for_github_actions.ps1](github-actions.md)   
