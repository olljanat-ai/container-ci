# Playbook: bump a pinned version

Every version in this repository appears in more than one file. Missing one leaves the
three pipelines running different tool versions, which is exactly the drift this design
exists to prevent.

## 1. Find the real version

Never guess it, and never carry one over from memory.

```bash
# Latest tags for a GitHub project
git ls-remote --tags --refs https://github.com/aquasecurity/trivy.git \
  | awk -F/ '{print $NF}' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -5

# Latest AVM module version
curl -s https://registry.terraform.io/v1/modules/Azure/avm-res-containerregistry-registry/azurerm/versions \
  | python3 -c "import json,sys; print([v['version'] for v in json.load(sys.stdin)['modules'][0]['versions']][-5:])"
```

For a GitHub Action, resolve the tag to a commit SHA — the repository pins actions by
SHA, with the tag as a trailing comment:

```bash
tag=v0.36.0; repo=aquasecurity/trivy-action
git ls-remote "https://github.com/$repo.git" "refs/tags/$tag^{}" \
  || git ls-remote "https://github.com/$repo.git" "refs/tags/$tag"
```

The fallback matters: lightweight tags have no `^{}` peel and the first command returns
nothing.

## 2. Update every file

Check the change matrix in [`../context.md`](../context.md). As of now:

### Trivy

| File | What to change |
| --- | --- |
| `.github/workflows/build-and-push.yml` | `env.TRIVY_VERSION` |
| `pipelines/azure-devops/templates/container-build.yml` | `trivyVersion` parameter default |
| `pipelines/gitlab/templates/container-build.yml` | `trivy_version` input default |
| `ai/context.md` | pinned versions table |
| `docs/index.template.html` | masthead `Trivy 0.74` |

Note the version-string shapes differ: GitHub takes `v0.74.0` (the action's `version`
input wants the `v`), Azure DevOps and GitLab take `0.74.0` because they interpolate it
into a release URL that already has the `v`.

### `aquasecurity/trivy-action`

Five occurrences in `.github/workflows/build-and-push.yml`. Update the SHA *and* the
`# vX.Y.Z` comment on each — a stale comment is worse than none.

### Aikido Safe Chain

The installer's SHA-256 changes with the version. Take it from the release's README
snippet, then verify:

```bash
version=1.5.18
curl -fsSL "https://github.com/AikidoSec/safe-chain/releases/download/${version}/install-safe-chain.sh" | sha256sum
```

| File | What to change |
| --- | --- |
| `pipelines/common/Dockerfile` | `ARG SAFE_CHAIN_VERSION`, `ARG SAFE_CHAIN_SHA256` |
| `pipelines/common/Dockerfile.python` | same two ARGs |
| `pipelines/common/scripts/install-safe-chain.sh` | the two defaults at the top |
| `.github/workflows/build-and-push.yml` | `env.SAFE_CHAIN_VERSION`, `env.SAFE_CHAIN_SHA256` |
| `pipelines/azure-devops/templates/container-build.yml` | `safeChainVersion`, `safeChainSha256` defaults |
| `pipelines/gitlab/templates/container-build.yml` | `safe_chain_version`, `safe_chain_sha256` defaults |
| `ai/context.md` | pinned versions table |
| `docs/index.template.html` | masthead `Safe Chain 1.5` |

### AVM container registry module

`infra/terraform/main.tf` (`version = "0.8.0"`). The module is pre-1.0, so **read its
changelog** — a minor bump can rename or retype an input. Check that these are still
present and unchanged in shape before claiming the bump works: `role_assignment_mode`,
`scope_maps`, `cache_rules`, `credential_sets`, `retention_policy_in_days`,
`network_rule_set`, `role_assignments` (with `condition` and `condition_version`).

Then re-run `terraform init -upgrade` and commit the updated `.terraform.lock.hcl`.

## 3. Verify

```bash
python3 tools/build_docs.py
terraform -chdir=infra/terraform init -backend=false -upgrade
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform fmt -check -recursive
shellcheck pipelines/common/scripts/*.sh
```

Then grep for the version you replaced. A single hit left behind means a file was missed:

```bash
grep -rn "0\.73\.0\|1\.5\.17" --exclude-dir=.git .
```

## 4. Commit

Say what moved and what you verified. If the AVM bump changed an input shape, say which.
