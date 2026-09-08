# container-ci

A central container registry and the build pipelines that feed it.

One Premium **Azure Container Registry** shared by every project, deployed with
Terraform and the Azure Verified Module for ACR. Projects are separated by **repository
namespace**, enforced by Entra ABAC conditions rather than by convention. Three CI
systems — **Azure DevOps**, **GitHub Actions** and **GitLab CI** — implement one
identical build contract: scan the source, build, scan the image, and only then push.

**→ [Start here: the guidance site](docs/index.html)** — pick your CI system and follow
the setup. It is published to GitHub Pages by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml) on every push to `main`.

---

## What is in here

| Path | |
| --- | --- |
| [`infra/terraform/`](infra/terraform) | The registry, the tenant model, and one federated identity per pipeline |
| [`pipelines/`](pipelines) | The three pipelines and the build assets they share |
| [`docs/`](docs) | The guidance site, generated from the pipeline files themselves |
| [`ai/`](ai) | Context and playbooks so a change request can be one sentence |
| [`.github/workflows/build-and-push.yml`](.github/workflows/build-and-push.yml) | The reusable workflow other repositories call |

## The design in short

**Multi-tenancy by namespace.** The registry runs in `AbacRepositoryPermissions` mode.
Every grant is an Azure role assignment carrying an ABAC condition pinned to a tenant's
repository prefixes, so the payments team's pipeline can write to `payments/` and
nowhere else. Everyone can read `shared/` (golden base images) and `cache/`
(pull-through cache of Docker Hub and MCR).

**Public on the network, closed by authorization.** Hosted CI runners have no stable
egress address, so an IP allowlist would put every team on self-hosted runners. The
registry stays reachable; the admin account is disabled, anonymous pull is off, and every
pipeline authenticates as itself.

**No registry passwords.** Each pipeline gets a user-assigned managed identity with a
federated credential pinned to its repository and branch. The job's own OIDC token is
exchanged for an Azure token, then for an ACR refresh token. There is no secret to
rotate and none to leak.

**Scan before push.** The image is built on the runner and held there until Trivy has
cleared both the source tree and the finished image. A vulnerable image never reaches a
registry every project can read.

**Malicious packages blocked at install time.**
[Aikido Safe Chain](https://github.com/AikidoSec/safe-chain) proxies npm and PyPI
downloads through Aikido Intel — on the runner *and* inside the Dockerfile's build stage,
because `npm ci` inside `docker build` runs where the runner's shims do not exist.

**One policy, three platforms.** [`pipelines/common/trivy.yaml`](pipelines/common/trivy.yaml)
is loaded by all three. Changing what fails a build is a one-file change.

## Quick start

```bash
# 1. Deploy the registry
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars    # add your tenants
export ARM_SUBSCRIPTION_ID=<subscription-id>
az login && terraform init && terraform apply

# 2. Collect what the pipelines need
terraform output login_server
terraform output azure_tenant_id
terraform output -json ci_identities
```

Then follow the guidance site, or the README for your platform:
[Azure DevOps](pipelines/azure-devops/README.md) ·
[GitHub Actions](pipelines/github/README.md) ·
[GitLab CI](pipelines/gitlab/README.md).

## Changing things

Read [`CLAUDE.md`](CLAUDE.md) and [`ai/context.md`](ai/context.md) first. The change
matrix there lists which files have to move together for each kind of change — most
defects in a repository shaped like this one are a change landing in three of the four
places it belongs.

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false && terraform -chdir=infra/terraform validate
shellcheck pipelines/common/scripts/*.sh
python3 tools/build_docs.py --check
```

[`.github/workflows/checks.yml`](.github/workflows/checks.yml) runs the same set on every
pull request, including the check that `docs/index.html` is still in sync with the
pipeline files it embeds.

## Status

The Terraform is validated and its tenant logic has been exercised against sample input;
the pipelines are validated as YAML and their shared policy and scripts are checked in
CI, but they have not yet been run end to end against a live registry. Treat the first
run of each as the acceptance test.

## Licence

[MIT](LICENSE).
