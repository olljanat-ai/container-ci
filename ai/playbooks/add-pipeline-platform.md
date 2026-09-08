# Playbook: add a CI platform

Adding a fourth platform (Bitbucket Pipelines, Jenkins, CircleCI, Woodpecker) means
implementing the same seven-step contract and registering it in eight places. Implement
the contract exactly — a platform that skips a step is worse than no support, because it
looks supported.

## 1. Check the platform can do the two hard things

Before writing YAML, confirm:

- **OIDC / workload identity federation.** The platform must mint a job token whose
  issuer and subject can be pinned in a federated credential. If it cannot, the only
  option is the scope-map token fallback in `var.tenants[*].token` — a long-lived
  password. Say so up front rather than discovering it at the end.
- **Docker builds.** The job needs a Docker daemon or BuildKit, and the ability to keep
  the built image locally so it can be scanned before it is pushed. A platform that can
  only build-and-push in one shot cannot implement this contract.

Record the issuer and subject formats — you will need them in `ai/context.md`.

## 2. Implement the contract

Copy the closest existing template. GitLab's is the best starting point for a container-
native platform; Azure DevOps' is closer for a step-based one.

The seven steps, from [`../context.md`](../context.md#the-build-contract):

1. Install Safe Chain (`--ci`), pinned by version and SHA-256, and put its shims ahead of
   the real package managers on `PATH`.
2. `trivy fs` twice — report pass (`--exit-code 0`, full severity, SARIF) then gate pass
   (`--severity HIGH,CRITICAL --exit-code 1`).
3. `docker build`, passing `REGISTRY`, `SAFE_CHAIN_VERSION` and `SAFE_CHAIN_SHA256` as
   build arguments. The image is **not** pushed here.
4. `trivy image` twice, same shape.
5. `trivy image --format cyclonedx` as a build artifact.
6. Authenticate: exchange the job's OIDC token for an Entra token, then exchange that at
   `https://<registry>/oauth2/exchange` for an ACR refresh token, then `docker login`
   with username `00000000-0000-0000-0000-000000000000`.
7. Push, tagged with the full commit SHA; `latest` on the default branch only; never on a
   pull or merge request.

Two things to get right:

- **Safe Chain goes in the Dockerfile too**, not just the runner. The runner install does
  not reach `npm ci` inside `docker build`.
- **Keep the two Trivy passes separate.** A combined pass reports either too little or
  fails on `LOW`.

If the platform has no Azure CLI available, copy GitLab's approach: obtain the Entra
token with a plain `curl` to the OAuth2 token endpoint using the job token as a client
assertion.

## 3. Register it in all eight places

| # | Where | What |
| --- | --- | --- |
| 1 | `pipelines/<platform>/templates/` | The shared template or component |
| 2 | `pipelines/<platform>/` | A caller example a team copies into their repository |
| 3 | `pipelines/<platform>/README.md` | Prerequisites, variables, what runs, troubleshooting — mirror an existing one |
| 4 | `pipelines/README.md` | Row in the platform table |
| 5 | `docs/assets/app.js` | Add the slug to `TOOLS` |
| 6 | `docs/assets/style.css` | Add the two `body[data-active="<slug>"]` selector pairs |
| 7 | `docs/index.template.html` | A `.chooser__option` button, a `<div data-tool="<slug>">` in `#setup`, a troubleshooting block, and an `{{include:}}` for the caller file |
| 8 | `ai/context.md` | Issuer/subject row, and every affected row of the change matrix |

Also update `ai/prompts.md` if the platform introduces a new kind of request.

The two CSS selector groups in step 6 are easy to half-do — one is for `[data-tool]`
blocks that are plain (`display: block`) and one for `section[data-tool]` blocks that are
flex containers. Miss the second and a whole section silently collapses.

## 4. Verify

```bash
python3 -c "import yaml,sys; list(yaml.safe_load_all(open('pipelines/<platform>/...')))"
python3 tools/build_docs.py
```

Open `docs/index.html` and click through all four chooser options — every section must
show content for each, and none should show two platforms' content at once.

Then run the pipeline for real against a scratch tenant. A CI template that has never
executed is a draft, and should be described as one.
