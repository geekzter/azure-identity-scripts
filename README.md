# Azure Active Directory Scripts

[![azure-cli-ci](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/geekzter/azure-active-directory-scripts/actions/workflows/ci.yml)

This repo contains a few scripts I use to create or find Azure Active Directory objects:

- Service Principal for GitHub Actions with Workload Identity (OpenID Connect) pattern: [create_sp_for_github_actions.ps1](github-actions.md)   
- Find Service Principal or Application by UUID: [find_sp_by_id.ps1](scripts/find_sp_by_id.ps1)

I typically use [PowerShell](https://github.com/PowerShell/PowerShell) with the [Azure CLI](https://github.com/Azure/azure-cli).