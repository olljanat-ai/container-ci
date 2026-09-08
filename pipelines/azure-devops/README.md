# Azure DevOps Pipelines

## What you need

1. **A service connection using workload identity federation.** In the project:
   *Project settings → Service connections → New → Azure Resource Manager →
   Workload Identity federation (manual)*. Enter the subscription and the
   `client_id` of the tenant's managed identity from
   `terraform output -json ci_identities`.

   Azure DevOps then shows an **Issuer** and a **Subject identifier**. Those are
   the values Terraform needs — this is a two-step dance, because the service
   connection has to exist before its subject does:

   ```hcl
   ci_identities = {
     build = {
       access  = "push"
       issuer  = "https://vstoken.dev.azure.com/<organization-id>"
       subject = "sc://<organization>/<project>/acr-push"
     }
   }
   ```

   Create the identity first with a placeholder subject, create the service
   connection with the resulting `client_id`, then copy the real issuer and
   subject back into `terraform.tfvars` and re-apply. The pipeline cannot
   authenticate until the subject matches exactly, which is what stops another
   project's service connection from using this identity.

2. **A GitHub service connection** named `github-container-ci` so the pipeline can
   consume this repository as a template resource. If you mirror this repository
   into Azure Repos instead, change the `resources.repositories` entry to
   `type: git` and drop the `endpoint`.

3. `Dockerfile`, `trivy.yaml` and `.trivyignore` in the repository root. Start from
   [`pipelines/common`](../common).

## Wiring it up

Copy [`azure-pipelines.yml`](azure-pipelines.yml) into your repository root and edit
`registry`, `image` and `azureServiceConnection`. The build lives in
[`templates/container-build.yml`](templates/container-build.yml).

## What runs

| Step | Purpose |
| --- | --- |
| Install Aikido Safe Chain | Shims npm/pip on the agent so anything the *pipeline* installs is checked against Aikido Intel |
| Install Trivy | Pinned release, with the vulnerability database cached between runs by `Cache@2` |
| `trivy fs` (report + gate) | Dependency CVEs, secrets and Dockerfile misconfiguration |
| `docker build` | The image stays on the agent. Safe Chain is installed inside the Dockerfile's build stage, which is what protects `npm ci` *inside* the image |
| `trivy image` (report + gate) | Scans the built image; nothing is pushed until it passes |
| SBOM | CycloneDX SBOM published as a build artifact |
| `AzureCLI@2` | Federated sign-in, token exchange, push |

Trivy runs twice per target on purpose: a full-severity pass that produces the SARIF
artifact, then a HIGH/CRITICAL pass that decides whether the build fails. The database
is shared, so the second pass is quick.

Pull request builds run every scan but skip the push — the step is guarded by
`ne(variables['Build.Reason'], 'PullRequest')`.

## Tagging

Every image is tagged with the full commit SHA (`$(Build.SourceVersion)`), so a
deployment always names an exact build. Builds of `defaultBranch` additionally get
`latest`.

## Self-hosted agents

The template installs Trivy and Safe Chain per run, which suits Microsoft-hosted
agents. On a self-hosted pool, bake both into the agent image and delete those two
steps — but keep `safe-chain --version`, so a broken agent image fails loudly instead
of silently skipping the malware check.

The `sudo mv` in the Trivy install step assumes a passwordless-sudo agent. If yours is
not, install Trivy to `$(Agent.ToolsDirectory)` and prepend that to `PATH` instead.

## Troubleshooting

**`AADSTS700213` / `No matching federated identity record found`**
The service connection's subject does not match the `subject` in `terraform.tfvars`.
Re-read it from the service connection page — it changes if the connection or project
is renamed.

**`denied: requested access to the resource is denied` on push**
The image name is outside the tenant's namespace. Check the first path segment against
`terraform output tenant_namespaces`.

**The template resource cannot be resolved**
The GitHub service connection named in `resources.repositories[].endpoint` does not
exist or lacks access to this repository.
