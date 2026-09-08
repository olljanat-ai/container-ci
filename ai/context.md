# Context

Everything an agent needs to change this repository correctly without being re-briefed.
If a fact here goes stale, fix it here first — the playbooks and the site both lean on it.

---

## The system in six sentences

One Premium Azure Container Registry is shared by every project. Projects are separated
by **repository namespace** (`payments/`, `web/`, …), enforced by Azure ABAC conditions
on role assignments rather than by convention or by network rules. The registry is
public on the network because hosted CI runners have no stable egress address;
authorization does the isolation instead. Each pipeline gets a user-assigned managed
identity with a federated credential, so CI authenticates over OIDC and no registry
password exists anywhere. Three CI systems — Azure DevOps, GitHub Actions, GitLab CI —
implement one identical seven-step build contract. The guidance site in `docs/` is
generated from the pipeline files themselves so it cannot drift from them.

---

## Pinned versions

Change these only via [`playbooks/bump-tool-versions.md`](playbooks/bump-tool-versions.md),
which lists every file each one appears in.

| Thing | Version | Verify with |
| --- | --- | --- |
| Trivy | `0.74.0` | `git ls-remote --tags https://github.com/aquasecurity/trivy` |
| `aquasecurity/trivy-action` | `v0.36.0` @ `ed142fd0673e97e23eac54620cfb913e5ce36c25` | `git ls-remote https://github.com/aquasecurity/trivy-action refs/tags/v0.36.0` |
| Aikido Safe Chain | `1.5.18` | releases page; the SHA-256 is published in the project README |
| Safe Chain installer SHA-256 | `bdbc58829853e598c09874fcc193f7cdb2a9a848875be45260a8b59bc4ce5439` | `curl -fsSL <release url> \| sha256sum` |
| AVM ACR module | `0.8.0` | `curl -s https://registry.terraform.io/v1/modules/Azure/avm-res-containerregistry-registry/azurerm/versions` |
| Terraform | `>= 1.9` | — |
| `azurerm` provider | `>= 4.81.0, < 5.0.0` | pinned by the AVM module's requirements |
| Docker images in GitLab CI | `docker:28-cli`, `docker:28-dind` | Docker Hub tags |
| Node base image | `node:22-bookworm-slim` | via the registry cache |
| Python base image | `python:3.13-slim-bookworm` | via the registry cache |

### GitHub Actions, pinned by SHA

| Action | Tag | SHA |
| --- | --- | --- |
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `azure/login` | v3.0.2 | `7ddb5af1ef8758cf1353cf3b42f940aee27ba21c` |
| `aquasecurity/trivy-action` | v0.36.0 | `ed142fd0673e97e23eac54620cfb913e5ce36c25` |
| `docker/setup-buildx-action` | v4.3.0 | `37fe631027851001ddb9b187196cc803df7f5f0e` |
| `docker/build-push-action` | v7.3.0 | `53b7df96c91f9c12dcc8a07bcb9ccacbed38856a` |
| `docker/metadata-action` | v6.2.0 | `dc802804100637a589fabce1cb79ff13a1411302` |
| `github/codeql-action` | v4.37.9 | `cdf488f595d80d6e07e03d4674febd5ab45fa938` |
| `actions/upload-artifact` | v7.0.1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/configure-pages` | v6.0.0 | `45bfe0192ca1faeb007ade9deae92b16b8254a0d` |
| `actions/upload-pages-artifact` | v5.0.0 | `fc324d3547104276b827a68afc52ff2a11cc49c9` |
| `actions/deploy-pages` | v5.0.1 | `368f82528645a54fb793d4d04e342629a3f51346` |

Resolve a tag to a SHA with:

```bash
git ls-remote https://github.com/<owner>/<repo>.git 'refs/tags/<tag>^{}' \
  || git ls-remote https://github.com/<owner>/<repo>.git 'refs/tags/<tag>'
```

(The fallback is for lightweight tags, which have no `^{}` peel.)

---

## Azure facts, verified against Microsoft Learn

Do not paraphrase these from memory — they are exact strings that Azure rejects if wrong.

### ABAC-enabled ACR roles

| `access` in `var.tenants` | Role name | Role definition GUID |
| --- | --- | --- |
| `pull` | Container Registry Repository Reader | `b93aa761-3e63-49ed-ac28-beffa264f7ac` |
| `push` | Container Registry Repository Writer | `2a1e307c-b015-4ebd-883e-5b7698a07328` |
| `contribute` | Container Registry Repository Contributor | `2efddaa5-3f1f-4df3-97df-af3f13818f4c` |
| (opt-in, no ABAC support) | Container Registry Repository Catalog Lister | `bfdb9389-c9a5-478a-bb2f-ba9ca092c3c7` |

Legacy `AcrPull` / `AcrPush` / `AcrDelete` are **not honoured** when
`role_assignment_mode = "AbacRepositoryPermissions"`.

### Repository data actions

These are the complete `dataActions` of the roles above, and are what
`local.repository_actions` in `infra/terraform/locals.tf` mirrors:

```
Microsoft.ContainerRegistry/registries/repositories/content/read
Microsoft.ContainerRegistry/registries/repositories/content/write
Microsoft.ContainerRegistry/registries/repositories/content/delete
Microsoft.ContainerRegistry/registries/repositories/metadata/read
Microsoft.ContainerRegistry/registries/repositories/metadata/write
Microsoft.ContainerRegistry/registries/repositories/metadata/delete
```

**An ABAC condition only constrains the actions it names.** Any data action a role
carries but the condition omits stays registry-wide. This is the single most dangerous
thing to get wrong in this repository: dropping an action from
`local.repository_actions` silently widens a grant to every repository.

### ABAC condition shape

```
(
 (
  !(ActionMatches{'<action 1>'})
  AND
  !(ActionMatches{'<action 2>'})
 )
 OR 
 (
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '<prefix>/'
 )
)
```

`condition_version` is `"2.0"`. The attribute source is `@Request`, not `@Resource`.
The trailing `/` on the prefix is required: without it, `payments` also matches
`payments-archive/secrets`.

### OIDC issuers and subjects

| Platform | Issuer | Subject |
| --- | --- | --- |
| GitHub Actions | `https://token.actions.githubusercontent.com` | `repo:<owner>/<repo>:ref:refs/heads/main`, `repo:<owner>/<repo>:environment:<name>`, `repo:<owner>/<repo>:pull_request` |
| GitLab CI | `https://gitlab.com` or the instance URL | `project_path:<group>/<project>:ref_type:branch:ref:main` |
| Azure DevOps | `https://vstoken.dev.azure.com/<organization-id>` | `sc://<organization>/<project>/<service-connection-name>` |

Audience is `api://AzureADTokenExchange` everywhere.

### Registry sign-in

The pipelines do **not** use `az acr login`. It resolves the registry through ARM first,
which needs `Microsoft.ContainerRegistry/registries/read` — a control-plane permission
the pipeline identities deliberately do not hold. Instead they exchange the Entra access
token for an ACR refresh token:

```
POST https://<login-server>/oauth2/exchange
grant_type=access_token&service=<login-server>&tenant=<tenant-id>&access_token=<entra-token>
```

and `docker login` with username `00000000-0000-0000-0000-000000000000` and that refresh
token as the password. This is the same exchange `az acr login` performs internally.
GitLab goes one step further and obtains the Entra token itself with the OAuth2
client-credentials flow plus a federated client assertion, so the `docker:cli` image
needs no Azure CLI.

---

## The build contract

All three pipelines run these steps in this order. Reordering them breaks the guarantee
that the shared registry only ever receives scanned images.

1. Install Aikido Safe Chain on the runner (`--ci`, shims not aliases).
2. `trivy fs` — report pass (all severities, SARIF) then gate pass (`HIGH,CRITICAL`).
3. `docker build`. Safe Chain is **also** installed in the Dockerfile's build stage.
4. `trivy image` — report pass then gate pass, against the local image.
5. `trivy image --format cyclonedx` — SBOM artifact.
6. Authenticate to Azure over OIDC, then exchange for an ACR refresh token.
7. Push. Never on a pull request or merge request.

Two things people get wrong when editing these:

- **Safe Chain belongs in two places.** The runner install does not cover `npm ci` inside
  `docker build`, which runs in the build container where the runner's shims do not exist.
- **Trivy runs twice per target on purpose.** With `format: sarif` the trivy-action unsets
  `TRIVY_SEVERITY` so the report contains every severity; a single combined pass would
  therefore fail the build on `LOW` findings. Keep the passes separate.

---

## Change matrix

The column count is the point. A change that lands in fewer files than listed is
incomplete.

| Change | Files that must move together |
| --- | --- |
| Trivy version | `.github/workflows/build-and-push.yml` (`env.TRIVY_VERSION`), `pipelines/azure-devops/templates/container-build.yml` (`trivyVersion`), `pipelines/gitlab/templates/container-build.yml` (`trivy_version`), `ai/context.md`, masthead in `docs/index.template.html` |
| `trivy-action` version | `.github/workflows/build-and-push.yml` (5 occurrences, SHA + comment), `ai/context.md` |
| Safe Chain version or checksum | `pipelines/common/Dockerfile`, `pipelines/common/Dockerfile.python`, `pipelines/common/scripts/install-safe-chain.sh`, `.github/workflows/build-and-push.yml`, `pipelines/azure-devops/templates/container-build.yml`, `pipelines/gitlab/templates/container-build.yml`, `ai/context.md`, masthead in `docs/index.template.html` |
| Scan policy (what fails a build) | `pipelines/common/trivy.yaml` only — plus prose in `pipelines/README.md` and the `#scanning` section of `docs/index.template.html` if the rationale changes |
| A build step added, removed or reordered | all three pipeline files, `pipelines/README.md`, the `.steps` list in `docs/index.template.html` |
| A new tenant | `infra/terraform/terraform.tfvars` (not committed) — nothing else |
| Tenant *schema* (a new field on `var.tenants`) | `infra/terraform/variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `infra/terraform/README.md`, `ai/playbooks/add-tenant.md` |
| Registry configuration | `infra/terraform/variables.tf` + `main.tf`, `infra/terraform/README.md`, the "Deliberate choices" table in `docs/index.template.html` |
| A new CI platform | see [`playbooks/add-pipeline-platform.md`](playbooks/add-pipeline-platform.md) — 8 places |
| Anything included by the site | re-run `python3 tools/build_docs.py` |
| The site's publishing setup | `.github/workflows/pages.yml`, `docs/README.md`, `README.md`, `ai/playbooks/update-docs-site.md` |

`{{include:…}}` in `docs/index.template.html` currently pulls:

- `pipelines/azure-devops/azure-pipelines.yml`
- `pipelines/github/workflows/container.yml`
- `pipelines/gitlab/.gitlab-ci.yml`
- `pipelines/common/trivy.yaml`
- `pipelines/common/Dockerfile`

Those five need no manual copy into the page. Everything else on the page is hand-written
and does need updating.

---

## Verification

Run before committing; CI runs the same set.

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
shellcheck pipelines/common/scripts/*.sh
trivy config --config pipelines/common/trivy.yaml pipelines/common
python3 tools/build_docs.py --check
```

`terraform validate` does not exercise the tenant logic, because the interesting parts
are `locals` that only resolve with real input. To test those without an Azure
subscription, copy `variables.tf` and `locals.tf` into a scratch directory, stub the
`azurerm_user_assigned_identity.ci[…].principal_id` reference in
`local.catalog_lister_principals` with a literal GUID, add outputs for
`local.abac_conditions` and `local.tenants`, and `terraform apply` it. That is how the
current conditions were checked.
