# Central container registry — Terraform

Deploys one **Premium Azure Container Registry** shared by every project, using the
[Azure Verified Module `Azure/avm-res-containerregistry-registry/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm/0.8.0)
(pinned to `0.8.0`).

## What this builds

| Piece | Why |
| --- | --- |
| Premium registry | Required for ABAC repository permissions, geo-replication, scope maps, cache rules, IP rules and the untagged-manifest retention policy |
| `role_assignment_mode = "AbacRepositoryPermissions"` | Lets a single registry be split into per-tenant repository namespaces |
| Public network access | Hosted CI runners have no stable egress IP; keeping the registry public means no self-hosted runners are needed |
| System-assigned identity | Used by the registry itself, e.g. for customer-managed keys |
| Pull-through cache rules | Builds pull base images through `cache/…` instead of hitting Docker Hub, so the anonymous rate limit is off the critical path |
| One user-assigned identity + federated credential per pipeline | Pipelines authenticate with OIDC; no registry password is ever stored in a CI system |
| Optional scope maps and tokens | Fallback for runners that cannot do workload identity federation |

The admin account stays disabled — it is a shared credential that bypasses every
per-tenant boundary below.

## The multi-tenancy model

Tenants share one registry and are separated by **repository namespace**:

```
contosocentralregistry.azurecr.io
├── shared/…            every tenant can read, only the platform team can write
├── cache/…             pull-through cache of docker.io and mcr.microsoft.com
├── payments/api        payments tenant
├── payments/worker
└── web/frontend        web tenant
```

Each grant becomes an Azure RBAC role assignment on the registry, carrying an ABAC
condition that pins it to the tenant's prefixes:

```
(
 (
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/write'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/write'})
 )
 OR
 (
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'payments/'
 )
)
```

Read it as: *unless the caller is performing one of these repository data actions this
assignment says nothing; if they are, the repository name must start with `payments/`.*

Two consequences worth knowing:

- **A condition only constrains the actions it names.** Any data action left out stays
  registry-wide. `local.repository_actions` therefore lists every data action the
  matching role carries — do not trim it.
- **The trailing slash is load-bearing.** `payments` without it also matches
  `payments-archive/secrets`. `var.tenants` validates this.

| `access` | Role assigned | Can |
| --- | --- | --- |
| `pull` | Container Registry Repository Reader | pull images, read tags and metadata |
| `push` | Container Registry Repository Writer | pull, push, retag (no delete) |
| `contribute` | Container Registry Repository Contributor | pull, push, delete images and tags |

`pull` grants cover the tenant's own namespaces **plus** `var.shared_read_namespaces` and
`extra_read_namespaces`. `push` and `contribute` are confined to the tenant's own
namespaces, so no tenant can write into `shared/` or into another tenant's space. A
push identity additionally receives a read-only assignment over the shared namespaces
so its builds can pull base images.

Listing repository *names* is a separate role — `Container Registry Repository Catalog
Lister` — which does not accept ABAC conditions, so granting it exposes every repository
name (names only, no content) in the registry. It is opt-in per tenant via
`catalog_lister = true`.

## Usage

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # then edit
export ARM_SUBSCRIPTION_ID=<subscription-id>
az login

terraform init
terraform plan
terraform apply
```

Wire the outputs into the CI platforms:

```bash
terraform output login_server
terraform output azure_tenant_id
terraform output -json ci_identities     # client_id per pipeline identity
terraform output -json registry_tokens   # sensitive; only for the token fallback
```

State is local by default. For anything shared, add a backend — for example:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatecontoso"
    container_name       = "tfstate"
    key                  = "container-registry.tfstate"
    use_azuread_auth     = true
  }
}
```

## Adding a tenant

Add one entry to `var.tenants` and apply. Nothing else changes:

```hcl
tenants = {
  # …existing tenants…

  analytics = {
    display_name = "Analytics"

    ci_identities = {
      build = {
        access  = "push"
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:contoso/analytics:ref:refs/heads/main"
      }
    }
  }
}
```

`terraform output -json ci_identities` then gives you the `client_id` to configure in the
pipeline. See [`ai/playbooks/add-tenant.md`](../../ai/playbooks/add-tenant.md) for the
end-to-end checklist, including the pipeline side.

### OIDC issuer and subject per platform

The federated credential only accepts a token whose `iss` and `sub` match exactly. That
match is what stops one repository from assuming another tenant's identity.

| Platform | `issuer` | `subject` |
| --- | --- | --- |
| GitHub Actions | `https://token.actions.githubusercontent.com` | `repo:<owner>/<repo>:ref:refs/heads/main`, `repo:<owner>/<repo>:environment:<name>`, or `repo:<owner>/<repo>:pull_request` |
| GitLab CI (SaaS) | `https://gitlab.com` | `project_path:<group>/<project>:ref_type:branch:ref:main` |
| GitLab CI (self-managed) | your instance URL | as above |
| Azure DevOps | `https://vstoken.dev.azure.com/<organization-id>` | `sc://<organization>/<project>/<service-connection-name>` |

For Azure DevOps the issuer and subject are shown on the service connection itself, under
**Manage Managed Identity / Workload Identity federation**. Create the service connection
in manual mode using the `client_id` this configuration outputs, then copy the issuer and
subject back into `terraform.tfvars`.

## Notes on switching an existing registry to ABAC mode

`AbacRepositoryPermissions` does **not** honour legacy `AcrPull` / `AcrPush` / `AcrDelete`
assignments, and switching modes invalidates registry credentials clients have already
cached — they get HTTP 401 until they refresh. On a live registry, assign the ABAC roles
first (without conditions, which is registry-wide and equivalent to the legacy role),
switch the mode, force clients to refresh, then narrow the conditions and remove the
legacy assignments. Microsoft's
[migration guide](https://learn.microsoft.com/azure/container-registry/container-registry-rbac-abac-repository-permissions#migrate-from-rbac-only-to-abac-enabled-mode)
has the full sequence.

ACR Tasks, `az acr build` and `az acr run` also lose their implicit data-plane access in
ABAC mode. This repository's pipelines build with Docker/BuildKit on the CI runner rather
than with ACR Tasks, so that change does not affect them.
