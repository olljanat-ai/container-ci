# Pipelines

Three implementations of one build contract. Pick the directory that matches your CI
system; the shared assets in [`common/`](common) are the same for all of them.

| | |
| --- | --- |
| [`azure-devops/`](azure-devops) | Azure Pipelines template plus a caller `azure-pipelines.yml` |
| [`github/`](github) | Caller workflow for the reusable workflow in [`.github/workflows/build-and-push.yml`](../.github/workflows/build-and-push.yml) |
| [`gitlab/`](gitlab) | GitLab CI component plus a caller `.gitlab-ci.yml` |
| [`common/`](common) | Dockerfiles, `trivy.yaml`, `.trivyignore`, `.dockerignore` and the shared shell scripts |

## The contract

Every pipeline runs the same seven steps in the same order:

1. **Install Aikido Safe Chain** on the runner, in `--ci` mode. Every later npm, pnpm,
   yarn, pip, uv or poetry call in the job is proxied through Aikido Intel; a package
   that is known malware at any dependency depth, or that was published inside the
   48-hour minimum age window, is blocked before it is written to disk.
2. **Scan the source with Trivy** — dependency CVEs from lock files, committed secrets,
   and Dockerfile misconfiguration.
3. **Build the image.** Safe Chain is installed *inside* the Dockerfile's build stage
   too. This is the part people usually miss: `npm ci` inside `docker build` runs in the
   build container, where the runner's shims do not exist, so a runner-only install
   leaves the image's own dependencies unprotected.
4. **Scan the built image with Trivy.**
5. **Generate a CycloneDX SBOM** and keep it as a build artifact.
6. **Authenticate to Azure over OIDC.** No registry password exists in any CI system.
7. **Push** — only after every scan has passed, and never from a pull or merge request.

Building before pushing is deliberate. The image is held on the runner until the scan
passes, so a vulnerable image never lands in a registry that every project can read.

## Why Trivy runs twice per target

The first pass writes a full-severity SARIF report so the platform's security view shows
everything. The second pass is filtered to `HIGH,CRITICAL` and is the one that fails the
build. Splitting them keeps the gate actionable without hiding the long tail. The
vulnerability database is cached between the two, so the second pass costs little.

Policy lives in one place — [`common/trivy.yaml`](common/trivy.yaml) — so a change to
what blocks a build is a one-file change across all three platforms. It gates on
*fixable* HIGH and CRITICAL findings: an unfixable CVE in a base image cannot be actioned
by the team that owns the application, and blocking on it only teaches people to bypass
the gate. Catch those with a scheduled `--ignore-unfixed=false` sweep instead.

## Image naming

```
<login-server>/<tenant-namespace>/<name>:<tag>
```

The first path segment must be your tenant's namespace. That is enforced by the ABAC
condition on the pipeline identity, not just by convention — a push to another tenant's
prefix returns `denied` regardless of what the pipeline asks for.

Tags:

- the full commit SHA on every build, so a deployment always names an exact build;
- `latest` on default-branch builds only;
- the version on tag builds.

## Base images

Pull base images through the registry's cache rather than from Docker Hub:

```dockerfile
ARG REGISTRY=docker.io
ARG NODE_IMAGE=${REGISTRY}/cache/docker-hub/library/node:22-bookworm-slim
```

The pipelines pass `REGISTRY` as a build argument. This takes Docker Hub's anonymous
rate limit off the critical path of every build, and means a base image your fleet
depends on is stored somewhere you control.
