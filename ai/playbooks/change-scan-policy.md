# Playbook: change what fails a build

Scan policy lives in exactly one file: `pipelines/common/trivy.yaml`. All three pipelines
load it, so the policy is a one-file change — that is the whole point of the design.

## Before changing it

Ask what problem the change solves. The two common requests pull in opposite directions:

- *"It's too noisy, stop failing on X"* — usually right when X cannot be actioned by the
  team that owns the application. Blocking on findings nobody can fix teaches people to
  route around the gate.
- *"We should also block on Y"* — usually right when Y is fixable and reaching production.

If a change makes builds pass that used to fail, say so plainly in the commit message.

## Common changes

### Severity threshold

```yaml
severity:
  - HIGH
  - CRITICAL
```

The pipelines also pass `--severity` on the gate pass, sourced from a parameter
(`trivy-severity` / `trivySeverity` / `trivy_severity`). Change both, or the CLI flag
silently wins:

- `.github/workflows/build-and-push.yml` → `inputs.trivy-severity` default
- `pipelines/azure-devops/templates/container-build.yml` → `trivySeverity` default
- `pipelines/gitlab/templates/container-build.yml` → `trivy_severity` default

### Blocking on unfixed vulnerabilities

```yaml
vulnerability:
  ignore-unfixed: false
```

Expect this to fail most builds immediately. The better shape is usually a scheduled
registry-wide sweep with `--ignore-unfixed=false` that raises tickets, leaving the build
gate on fixable findings. If asked for the sweep, add it as a new scheduled workflow
rather than changing this file.

### Adding a scanner

```yaml
scan:
  scanners:
    - vuln
    - secret
    - misconfig
    - license
```

`license` needs a `license:` block to be useful — at minimum `forbidden`. Without one it
reports everything and nothing blocks.

### End-of-life base images

`exit-on-eol` is deliberately `0`. The pipelines run Trivy twice per target, and a
non-zero exit from the *report* pass stops the SARIF being uploaded. To make EOL block,
add `--exit-on-eol 1` to the gate step in each pipeline rather than setting it here.

## Verify

```bash
trivy config --config pipelines/common/trivy.yaml pipelines/common
```

That both parses the config and runs the misconfiguration scanner over the reference
Dockerfiles — which must stay clean, since they are what teams copy.

Then check the key is real. Trivy silently ignores unknown config keys, so a typo looks
like a no-op:

```bash
trivy image --generate-default-config && cat trivy.yaml
```

Compare against <https://trivy.dev/latest/docs/references/configuration/config-file/>.
Note the traps: `ignore-unfixed` lives under `vulnerability:`, not at the top level, and
package types are `pkg.types`, not `vulnerability.type`.

## Update the prose

If the *rationale* changed — not just a number — update:

- the "Why unfixable findings do not block" text in `docs/index.template.html`
- the equivalent paragraph in `pipelines/README.md`

then `python3 tools/build_docs.py`.
