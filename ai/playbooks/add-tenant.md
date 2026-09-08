# Playbook: add or change a tenant

A tenant is a team or project. It owns one or more repository namespaces and gets
identities scoped to them. Adding one is a single Terraform entry — the namespaces, role
assignments, ABAC conditions and pipeline identity all follow.

## What you need before you start

- The tenant's short name. This becomes the repository namespace (`analytics` →
  `analytics/`) unless `repository_namespaces` overrides it.
- Which CI system its pipelines run on, and the repository or project path.
- Whether anything else needs to *pull* its images — an AKS cluster, Container Apps, a
  deployment service principal.

## 1. Add the tenant

In `infra/terraform/terraform.tfvars` (not committed; `terraform.tfvars.example` is the
committed reference):

```hcl
tenants = {
  # ...existing tenants...

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

`access` is one of:

| | Role | Can |
| --- | --- | --- |
| `pull` | Container Registry Repository Reader | pull, read tags and metadata |
| `push` | Container Registry Repository Writer | pull, push, retag — **not** delete |
| `contribute` | Container Registry Repository Contributor | pull, push, delete |

A build pipeline wants `push`. Use `contribute` only where something genuinely prunes
tags.

The issuer and subject formats for each platform are in
[`../context.md`](../context.md#oidc-issuers-and-subjects). Get the subject exactly
right — a mismatch fails at token exchange with `AADSTS70021`, which is the single most
common setup error.

### Azure DevOps is a two-step dance

The subject is `sc://<organization>/<project>/<service-connection-name>`, and the service
connection cannot be created until the managed identity exists. So:

1. Add the `ci_identities` entry with the subject you *intend* to use, and apply.
2. Create the service connection in manual mode with the resulting `client_id`.
3. Copy the issuer and subject Azure DevOps then displays back into `terraform.tfvars`
   and re-apply.

### Other identities

```hcl
analytics = {
  # ...

  # Something that only pulls, and already exists in Entra.
  principals = {
    aks_prod = {
      object_id      = "<kubelet identity principal ID>"
      access         = "pull"
      principal_type = "ServicePrincipal"
      description    = "aks-prod pulls analytics images"
    }
  }

  # Read another tenant's namespace as well as its own.
  extra_read_namespaces = ["shared-models/"]

  # Non-Entra fallback for a runner that cannot federate. ACR scope maps need
  # full repository names - prefixes are not accepted.
  token = {
    access          = "pull"
    repositories    = ["analytics/etl"]
    password_expiry = "2027-01-01T00:00:00Z"
  }
}
```

`object_id` is the **object ID**, not the application ID. For a managed identity it is
the `principal_id`; for an app registration it is the service principal's object ID, not
the app registration's.

Every namespace entry must end with `/`. Terraform rejects it otherwise, because
`analytics` without the slash also matches `analytics-archive/`.

## 2. Apply and read the outputs

```bash
cd infra/terraform
terraform plan     # review the role assignments and their conditions
terraform apply

terraform output -json ci_identities
terraform output tenant_namespaces
terraform output -json registry_tokens   # only if you configured `token`
```

Sanity-check the generated condition before you trust it:

```bash
terraform output -json abac_conditions | python3 -m json.tool
```

Each condition must name **every** data action its role carries. A missing action is not
a smaller grant — it is an unconstrained one.

## 3. Wire up the pipeline

Then follow the platform README, which lists the variables and the file to copy:

- [`pipelines/github/README.md`](../../pipelines/github/README.md)
- [`pipelines/azure-devops/README.md`](../../pipelines/azure-devops/README.md)
- [`pipelines/gitlab/README.md`](../../pipelines/gitlab/README.md)

## 4. Verify end to end

The first pipeline run is the test. If it fails:

| Symptom | Cause |
| --- | --- |
| `AADSTS70021` / `AADSTS700213` | subject mismatch — compare the token's `sub` against `terraform.tfvars` |
| `denied` on push | image name outside the namespace, or the assignment has not propagated |
| `unauthorized` pulling a base image | not using `<login-server>/cache/…`, or `cache/` missing from `shared_read_namespaces` |

## Things to push back on

- **`catalog_lister = true`.** That role does not accept ABAC conditions, so it exposes
  every repository *name* in the registry to that tenant. Say so before enabling it.
- **A `token` where federation would work.** A scope-map token is a long-lived password
  that has to be rotated. It exists for runners that genuinely cannot federate.
- **Wide `extra_read_namespaces`.** Granting `""` or a top-level prefix defeats the whole
  model.

## If you change the tenant *schema*

Adding a field to `var.tenants` is a bigger change than adding a tenant. It touches
`variables.tf` (type + validation + description), `locals.tf` (normalisation and grant
construction), `main.tf` (what it produces), `outputs.tf` if it should be visible,
`terraform.tfvars.example`, `infra/terraform/README.md`, and this playbook.
