# GitHub Actions

## What you need

1. A tenant in [`infra/terraform`](../../infra/terraform) with a `ci_identities` entry
   whose `subject` matches this repository and ref:

   ```hcl
   ci_identities = {
     build = {
       access  = "push"
       issuer  = "https://token.actions.githubusercontent.com"
       subject = "repo:contoso/payments-api:ref:refs/heads/main"
     }
   }
   ```

   The subject is checked on every token exchange, so another repository cannot
   assume this identity even if it knows the client ID.

   A repository that builds on tags or pull requests as well needs one
   `ci_identities` entry per subject — GitHub issues a different `sub` claim for
   `refs/heads/main`, `refs/tags/v1.2.3`, `pull_request` and each environment.
   Alternatively, add a GitHub Actions *environment* to the job and federate on
   `repo:<owner>/<repo>:environment:<name>`, which stays stable across refs.

2. Three repository variables (Settings → Secrets and variables → Actions → Variables):

   | Variable | Value |
   | --- | --- |
   | `AZURE_CLIENT_ID` | `client_id` from `terraform output -json ci_identities` |
   | `AZURE_TENANT_ID` | `terraform output azure_tenant_id` |
   | `AZURE_SUBSCRIPTION_ID` | `terraform output azure_subscription_id` |

   None of these is a secret. There is no registry password to store.

3. `Dockerfile`, `trivy.yaml` and `.trivyignore` in the repository root. Start from
   [`pipelines/common`](../common).

## Wiring it up

Copy [`workflows/container.yml`](workflows/container.yml) to
`.github/workflows/container.yml` and edit `registry`, `image` and the three
`azure-*` inputs. That is the whole integration — the build itself lives in the
central reusable workflow
[`.github/workflows/build-and-push.yml`](../../.github/workflows/build-and-push.yml).

## What runs

| Step | Purpose |
| --- | --- |
| Install Aikido Safe Chain | Shims npm/pip on the runner so anything the *job* installs is checked against Aikido Intel |
| `trivy fs` (report) | Full SARIF of dependency CVEs, secrets and Dockerfile misconfiguration → code scanning |
| `trivy fs` (gate) | Same scan filtered to HIGH/CRITICAL; fails the build |
| `docker build` | Builds with `load: true`, so the image stays local. Safe Chain is installed inside the Dockerfile's build stage, which is what protects `npm ci` *inside* the image |
| `trivy image` (report + gate) | Scans the built image; nothing is pushed until it passes |
| SBOM | CycloneDX SBOM uploaded as a build artifact |
| Sign in to Azure | OIDC federation — no stored credential |
| Push | Only on branch and tag builds; pull requests build and scan but never push |

Trivy runs twice per target on purpose. The reporting pass emits SARIF with every
severity so code scanning shows the full picture; the gating pass is filtered to
HIGH/CRITICAL so the build only fails on findings worth blocking on. The
vulnerability database is cached between the two, so the second pass is quick.

## Multi-architecture images

The default flow builds a single platform because the image has to be loaded into
the local Docker daemon to be scanned before it is pushed. For multi-arch, build and
scan each platform separately, push by digest, and assemble the manifest list
afterwards with `docker buildx imagetools create`.

## Troubleshooting

**`AADSTS70021: No matching federated identity record found`**
The token's subject does not match the federated credential. Print the claim the job
actually sends and compare it with `subject` in `terraform.tfvars`:

```yaml
- run: echo "${ACTIONS_ID_TOKEN_REQUEST_URL}"   # confirms id-token: write is granted
```

The common cause is building from a tag or a pull request when the credential was
federated on `ref:refs/heads/main`.

**`denied: requested access to the resource is denied` on push**
The image name is outside the tenant's namespace, or ABAC has not propagated yet.
Check the first path segment against `terraform output tenant_namespaces`.

**`unauthorized: authentication required` when pulling a base image**
Base images must come through the registry's pull-through cache
(`<login-server>/cache/docker-hub/library/node:22`), and the pipeline identity needs
read access to `cache/`, which it gets by default via `var.shared_read_namespaces`.
