output "login_server" {
  description = "Registry hostname, e.g. `contosocentralregistry.azurecr.io`. This is the value pipelines use as REGISTRY."
  value       = module.container_registry.login_server
}

output "registry_name" {
  description = "Name of the container registry."
  value       = module.container_registry.name
}

output "registry_resource_id" {
  description = "ARM resource ID of the registry. Use it as the `--scope` for any role assignment added outside Terraform."
  value       = module.container_registry.resource_id
}

output "tenant_namespaces" {
  description = "Repository prefixes each tenant may write to, and the wider set it may read."
  value = {
    for key, tenant in local.tenants : key => {
      write = tenant.write_namespaces
      read  = tenant.read_namespaces
    }
  }
}

output "ci_identities" {
  description = <<DESCRIPTION
Pipeline identities created for each tenant. Feed these into the CI platform:

- `client_id`    -> AZURE_CLIENT_ID (GitHub Actions, GitLab CI) or the workload identity federation service connection (Azure DevOps).
- `principal_id` -> object ID, if you need to grant the identity anything else.
- `subject`      -> the OIDC subject the federated credential accepts. A pipeline whose
                    token carries a different subject is rejected, which is what stops one
                    repository from assuming another tenant's identity.
DESCRIPTION
  value = {
    for key, grant in local.ci_identity_grants : key => {
      tenant       = grant.tenant_key
      access       = grant.access
      name         = azurerm_user_assigned_identity.ci[key].name
      client_id    = azurerm_user_assigned_identity.ci[key].client_id
      principal_id = azurerm_user_assigned_identity.ci[key].principal_id
      issuer       = grant.issuer
      subject      = grant.subject
    }
  }
}

output "azure_tenant_id" {
  description = "Entra tenant ID. Pipelines need this as AZURE_TENANT_ID."
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "Subscription hosting the registry. Pipelines that call `az acr` need this as AZURE_SUBSCRIPTION_ID."
  value       = data.azurerm_client_config.current.subscription_id
}

output "registry_tokens" {
  description = <<DESCRIPTION
Repository-scoped registry tokens for tenants that configured `token`. The map holds the
generated username and password for `docker login`. Sensitive: read it with
`terraform output -json registry_tokens` and place the value straight into the CI platform's
secret store.
DESCRIPTION
  sensitive   = true
  value = {
    for key in keys(local.tenant_scope_maps) : key => {
      username = "tok-${key}"
      password = try(module.container_registry.scope_maps[key].registry_token_passwords["default"].password1[0].value, null)
    }
  }
}

output "abac_conditions" {
  description = "The ABAC condition rendered for each grant. Useful when reviewing a plan or reproducing an assignment with `az role assignment create --condition`."
  value       = local.abac_conditions
}
