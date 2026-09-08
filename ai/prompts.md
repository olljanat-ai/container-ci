# Prompts that work

Requests you can make without re-explaining the repository. Each one names the playbook
the agent will follow.

## Versions

- *"Bump Trivy to the latest release."*
- *"Update Safe Chain to 1.6.0."*
- *"Update all the pinned GitHub Actions to their latest releases."*
- *"Move the AVM container registry module to the latest version."*

→ [`playbooks/bump-tool-versions.md`](playbooks/bump-tool-versions.md). The agent
resolves the real version and, where relevant, the real SHA-256 or commit SHA, updates
every file in the change matrix, and regenerates the site.

## Teams and access

- *"Add a team called analytics that builds on GitHub Actions from contoso/analytics."*
- *"Give the payments team read access to the web team's images."*
- *"The reporting team needs to delete old tags."*
- *"Let the platform team list every repository in the registry."*
- *"Add a token for the legacy Jenkins runner that can pull reporting/etl."*

→ [`playbooks/add-tenant.md`](playbooks/add-tenant.md).

## Scanning

- *"Stop failing builds on MEDIUM findings."*
- *"Start blocking on unfixed vulnerabilities too."*
- *"Add license scanning to the pipelines."*
- *"Fail the build if the base image is end-of-life."*

→ [`playbooks/change-scan-policy.md`](playbooks/change-scan-policy.md).

## Pipelines

- *"Add support for Bitbucket Pipelines."*
- *"Sign images with cosign after the scan passes."*
- *"Push multi-architecture images."*
- *"Run the source scan and the image build in parallel."*

→ [`playbooks/add-pipeline-platform.md`](playbooks/add-pipeline-platform.md) for a new
platform; otherwise the build-contract section of
[`context.md`](context.md), because a step change has to land in all three pipelines.

## Registry

- *"Replicate the registry to North Europe."*
- *"Restrict the registry to our office IP ranges."*
- *"Send registry logs to our Log Analytics workspace."*
- *"Add a pull-through cache for quay.io."*
- *"Turn on quarantine."*

→ [`playbooks/change-registry-config.md`](playbooks/change-registry-config.md).

## The site

- *"Add a FAQ section about image retention."*
- *"Show the Python Dockerfile on the page too."*
- *"Make the troubleshooting section platform-specific for Azure DevOps."*

→ [`playbooks/update-docs-site.md`](playbooks/update-docs-site.md).

## Requests that need a decision from you

These are not blocked, but the agent should ask rather than guess:

- Anything that would give a tenant registry-wide access — the catalog lister role, or an
  ABAC-enabled role with no condition.
- Turning the registry private, which forces every project onto self-hosted runners.
- Re-enabling the admin account, which is a shared credential that bypasses every
  namespace boundary.
- Switching `role_assignment_mode` on a registry that is already serving traffic, which
  invalidates cached client credentials.
