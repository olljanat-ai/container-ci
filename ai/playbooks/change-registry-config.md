# Playbook: change the registry configuration

The registry is `infra/terraform`, wrapping the AVM module
`Azure/avm-res-containerregistry-registry/azurerm` at `0.8.0`.

## Where things go

- A knob teams should be able to set → a variable in `variables.tf`, passed through in
  `main.tf`.
- Something derived from the tenants → `locals.tf`.
- Something worth reading back → `outputs.tf`.

Check the module actually supports the input first. It is pre-1.0 and its inputs are split
across `variables.tf`, `variables.containerregistry.tf` and `variables.cache_rules.tf`:

```bash
git clone --depth 1 --branch v0.8.0 \
  https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry.git /tmp/avm
grep -rn '^variable' /tmp/avm/*.tf
```

## Common changes

### Geo-replication

```hcl
geo_replications = [
  { location = "northeurope" },
]
```

Do not repeat `var.location` — the home region is already a replica. Each replica is
billed separately.

### IP restrictions

```hcl
allowed_ip_ranges = ["203.0.113.0/24"]
```

This flips the registry to deny-by-default. **It will break hosted CI runners**, whose
egress addresses rotate. Only do this when every pipeline runs on self-hosted runners
with fixed egress, and say so when proposing it.

### Diagnostics

```hcl
log_analytics_workspace_resource_id = "/subscriptions/.../workspaces/law-platform"
```

`ContainerRegistryLoginEvents` is the audit trail of who authenticated;
`ContainerRegistryRepositoryEvents` covers push, pull and delete.

### Pull-through cache

```hcl
cache_rules = {
  quay = {
    name              = "quay"
    source_repository = "quay.io/*"
    target_repository = "cache/quay/*"
  }
}
```

Anything under `cache/` is readable by every tenant via `var.shared_read_namespaces`.
Authenticated upstreams need a matching `credential_sets` entry, and that credential
set's managed identity needs `Key Vault Secrets User` on the referenced secrets — the
module does not grant that for you.

### Retention

`retention_policy_in_days` covers **untagged** manifests only. Tagged images are never
deleted by it. Tag cleanup needs an ACR purge task or a scheduled job holding
`contribute` on the namespace.

## Changes that need a conversation first

| Change | Why |
| --- | --- |
| `admin_enabled = true` | A shared username and password that bypasses every namespace boundary |
| `anonymous_pull_enabled = true` | Cannot be scoped per tenant — exposes every repository |
| `public_network_access_enabled = false` | Forces every project onto self-hosted runners |
| `role_assignment_mode` change on a live registry | Legacy `AcrPull`/`AcrPush` stop being honoured, and cached client credentials are rejected with HTTP 401 until they refresh. Follow Microsoft's staged migration |

## Verify

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan   # needs Azure credentials
```

`validate` does not catch a wrong input *value* — only a wrong shape. Read the plan.

## Update the docs

If the change alters a documented decision, update the "Deliberate choices" table in
`docs/index.template.html` and the corresponding section of `infra/terraform/README.md`,
then run `python3 tools/build_docs.py`.
