# GitLab CI

## What you need

1. A tenant in [`infra/terraform`](../../infra/terraform) with a `ci_identities` entry
   whose `subject` matches this project and ref:

   ```hcl
   ci_identities = {
     build = {
       access  = "push"
       issuer  = "https://gitlab.com" # your instance URL if self-managed
       subject = "project_path:contoso/payments-api:ref_type:branch:ref:main"
     }
   }
   ```

   The subject is checked on every token exchange, so another project cannot assume
   this identity even knowing the client ID. Tag pipelines produce
   `ref_type:tag:ref:<tag>`, so add a second entry if you build from tags.

2. Two CI/CD variables — on the group if several projects share the registry
   (*Settings → CI/CD → Variables*):

   | Variable | Value |
   | --- | --- |
   | `AZURE_CLIENT_ID` | `client_id` from `terraform output -json ci_identities` |
   | `AZURE_TENANT_ID` | `terraform output azure_tenant_id` |

   Neither is a credential, so neither needs masking or protection. There is no
   registry password to store.

3. `Dockerfile`, `trivy.yaml` and `.trivyignore` in the repository root. Start from
   [`pipelines/common`](../common).

## Wiring it up

Copy [`.gitlab-ci.yml`](.gitlab-ci.yml) into your repository root and edit `registry`
and `image`. The build lives in
[`templates/container-build.yml`](templates/container-build.yml).

If your GitLab instance mirrors this repository, point `include.project` at the mirror.
On GitLab.com pulling from GitHub, use `include.remote` with the raw file URL instead.

## What runs

| Step | Purpose |
| --- | --- |
| Install Aikido Safe Chain | Shims npm/pip in the job so anything the *job* installs is checked against Aikido Intel |
| Install Trivy | Pinned release; the vulnerability database is cached between pipelines |
| `trivy fs` (report + gate) | Dependency CVEs, secrets and Dockerfile misconfiguration |
| `docker build` | The image stays on the runner. Safe Chain is installed inside the Dockerfile's build stage, which is what protects `npm ci` *inside* the image |
| `trivy image` (report + gate) | Scans the built image; nothing is pushed until it passes |
| GitLab report + SBOM | `gl-container-scanning-report.json` renders in the merge request security widget; a CycloneDX SBOM is kept as an artifact |
| Push | OIDC only. Merge request pipelines scan but never push |

## How authentication works

GitLab mints an ID token for the job (`id_tokens.AZURE_ID_TOKEN`). The job trades it
for an Entra access token using the OAuth2 client-credentials flow with a federated
client assertion — the same exchange `az login --federated-token` performs, done with
`curl` so the `docker:cli` image needs no Azure CLI. That token is then exchanged at
`https://<registry>/oauth2/exchange` for an ACR refresh token, which is what
`docker login` uses.

The second exchange needs no control-plane permission, which matters because the
pipeline identity holds repository data-plane permissions only. `az acr login` resolves
the registry through ARM first and can fail with `ResourceNotFound` on a registry the
identity is perfectly entitled to push to.

## Docker-in-Docker

The template uses the `docker:28-dind` service with TLS. On a Kubernetes executor, dind
needs a privileged runner. If your runners use `--docker-privileged=false`, swap the
build step for BuildKit in rootless mode or a Kaniko job — the scan and push steps are
unchanged, because they only need the built image to exist locally.

## Troubleshooting

**`AADSTS70021: No matching federated identity record found`**
The token's subject does not match the federated credential. Print the claim the job
sends and compare it with `subject` in `terraform.tfvars`:

```yaml
- echo "$AZURE_ID_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{iss, sub, aud}'
```

The usual cause is a tag or merge request pipeline where the credential was federated
on `ref_type:branch:ref:main`.

**`denied: requested access to the resource is denied` on push**
The image name is outside the tenant's namespace. Check the first path segment against
`terraform output tenant_namespaces`.

**`Cannot connect to the Docker daemon`**
The dind service did not start, or `DOCKER_HOST`/`DOCKER_TLS_*` were overridden by a
group-level CI/CD variable.
