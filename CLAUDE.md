# Working in this repository

A central container registry and the build pipelines that feed it. Read this first;
it is short on purpose and points at the detail.

**Before changing anything, read [`ai/context.md`](ai/context.md).** It holds the pinned
versions, the invariants, and — most importantly — the change matrix: the list of files
that must move together for each kind of change. Most mistakes in this repository are
"changed it in two of the four places".

## What is here

| Path | |
| --- | --- |
| `infra/terraform/` | One Premium Azure Container Registry, deployed with the AVM module, plus per-tenant ABAC role assignments and pipeline identities |
| `pipelines/common/` | Reference Dockerfiles, the shared `trivy.yaml`, `.trivyignore`, shared shell scripts |
| `pipelines/azure-devops/` | Azure Pipelines template + caller |
| `pipelines/github/` | Caller workflow for the reusable workflow in `.github/workflows/` |
| `pipelines/gitlab/` | GitLab CI component + caller |
| `.github/workflows/build-and-push.yml` | The reusable workflow other repositories call. `workflow_call` only |
| `docs/` | The guidance site. **`index.html` is generated** — edit `index.template.html` |
| `tools/build_docs.py` | Renders the site from the template and the real pipeline files |
| `ai/` | Context and playbooks for exactly this kind of task |

## Playbooks

Named tasks have written procedures. Follow them rather than reconstructing the steps:

| You are asked to | Read |
| --- | --- |
| Add or change a team / project / tenant | [`ai/playbooks/add-tenant.md`](ai/playbooks/add-tenant.md) |
| Bump Trivy, Safe Chain, the AVM module, an action or an image | [`ai/playbooks/bump-tool-versions.md`](ai/playbooks/bump-tool-versions.md) |
| Change what fails a build | [`ai/playbooks/change-scan-policy.md`](ai/playbooks/change-scan-policy.md) |
| Support another CI system | [`ai/playbooks/add-pipeline-platform.md`](ai/playbooks/add-pipeline-platform.md) |
| Change the registry's configuration | [`ai/playbooks/change-registry-config.md`](ai/playbooks/change-registry-config.md) |
| Edit the guidance site | [`ai/playbooks/update-docs-site.md`](ai/playbooks/update-docs-site.md) |

## Rules that are not negotiable

1. **Never invent a version, a SHA-256, a role name, an Azure action string or an ABAC
   attribute.** Look it up. `ai/context.md` records where each one came from.
2. **The three pipelines implement one contract.** A change to any step must land in all
   three, or be explicitly justified as platform-specific in the commit message.
3. **`docs/index.html` is generated.** Run `python3 tools/build_docs.py` after touching
   the template or any file it includes. CI checks this.
4. **Scan before push, always.** The image is built on the runner and held there until
   every scan passes. Do not reorder those steps for speed.
5. **No registry passwords.** Pipelines authenticate with workload identity federation.
   The registry's admin account stays disabled. The only exception is the scope-map token
   fallback, which exists for runners that genuinely cannot federate.
6. **Repository namespaces end with `/`.** Without the trailing slash a prefix condition
   matches sibling namespaces. Terraform validates this; keep it that way.
7. **GitHub Actions are pinned by commit SHA** with the tag in a trailing comment.

## Checks before you commit

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false && terraform -chdir=infra/terraform validate
shellcheck pipelines/common/scripts/*.sh
python3 tools/build_docs.py --check
python3 -c "import yaml,sys,pathlib; [list(yaml.safe_load_all(p.read_text())) for p in pathlib.Path('.').rglob('*.yml')]"
```

`.github/workflows/checks.yml` runs the same set on every pull request.
