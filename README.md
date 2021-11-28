# github-action-azure-oidc

This repo demonstrates the use of [Workload identity federation][2] to configure a Service Principal without password secrets to act as the identity to access Azure from GitHub-hosted runners. There are 'howto' articles on both [GitHub Docs][3] and [Microsoft Docs][1], and the configuration is also documented on the [azure/login action][4].    
To set this up, configuration is required in 3 distinct services:
- Azure Active Directory: Service Principal configuration
- Azure: An RBAC role must be granted to a resource in Azure 
- GitHub: Service Principal information (excluding the key/password) must be configured as secrets
- GitHub: The action workflow YAML needs to be configured accordingly

To make life easier, this repo contains a [script](scripts/create_sp_for_github_actions.ps1) that configures the first 3 steps. In it most simple form it configures federation subjects for the repo where the script is executed from (e.g. geekzter/github-action-azure-oidc) for pull request, common branch names, the current branch, and the tag 'azure'.
```powershell
./create_sp_for_github_actions.ps1
```

You can specify another repo and override common parameters e.g.
```powershell
./create_sp_for_github_actions.ps1 -RepositoryName someowner/somereponame `
                                   -AzureRole Owner `
                                   -BranchNames mybranch 
```

You can also adapt the behavior to still create a password:
```powershell
./create_sp_for_github_actions.ps1 -CreateServicePrincipalPassword `
                                   -ConfigureAzureCredentialsJson `
                                   -SkipServicePrincipalFederation 
```

Sample output:
```
~/src/github/geekzter/github-action-azure-oidc/scripts> ./create_sp_for_github_actions.ps1 -AzureRule Owner
Logging into Azure...
Creating Service Principal with name 'geekzter-github-action-azure-oidc-cicd'...
WARNING: Found an existing application instance of "00000000-0000-0000-0000-000000000000". We will patch it
WARNING: Creating 'Contributor' role assignment under scope '/subscriptions/11111111-1111-1111-1111-111111111111'
WARNING: Creating 'Owner' role assignment under scope '/subscriptions/11111111-1111-1111-1111-111111111111'
WARNING:   Role assignment already exists.

WARNING: The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
WARNING: 'name' property in the output is deprecated and will be removed in the future. Use 'appId' instead.
Preparing federation subjects...
Retrieving existing federation subjects for Service Principal with client ID '00000000-0000-0000-0000-000000000000'...
Creating federation subjects for Service Principal with client ID '00000000-0000-0000-0000-000000000000'...
Created federation subjects for GitHub repo 'geekzter/github-action-azure-oidc'
Setting GitHub geekzter/github-action-azure-oidc secrets AZURE_CLIENT_ID, AZURE_TENANT_ID & AZURE_SUBSCRIPTION_ID...
? You're already logged into github.com. Do you want to re-authenticate? No
✓ Set secret AZURE_CLIENT_ID for geekzter/github-action-azure-oidc
✓ Set secret AZURE_TENANT_ID for geekzter/github-action-azure-oidc
✓ Set secret AZURE_SUBSCRIPTION_ID for geekzter/github-action-azure-oidc

Configure workflow YAML as per the azure/login action documentation:
https://github.com/marketplace/actions/azure-login

Service Principal in Azure Portal:
https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/00000000-0000-0000-0000-000000000000/isMSAApp/

Access Control list on scope '/subscriptions/11111111-1111-1111-1111-111111111111' in Azure Portal:
https://portal.azure.com/#@22222222-2222-2222-2222-222222222222/resource/subscriptions/11111111-1111-1111-1111-111111111111/users

Secrets on GitHub web:
https://github.com/geekzter/github-action-azure-oidc/settings/secrets/actions
```




[1]: https://docs.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cwindows
[2]: https://docs.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation
[3]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure
[4]: https://github.com/marketplace/actions/azure-login