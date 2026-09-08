#!/usr/bin/env bash
###############################################################################
# Install Aikido Safe Chain on a CI runner.
#
# `--ci` installs executable shims on PATH instead of shell aliases, so every
# later npm / pnpm / yarn / pip / uv / poetry invocation in the job is proxied
# through Aikido Intel and blocked if a package - at any depth - is known
# malware or was published within the minimum package age window.
#
# This protects what the *pipeline* installs. Packages installed inside
# `docker build` run in the build container and are not covered by the runner's
# shims: install Safe Chain in the Dockerfile's build stage as well. See
# pipelines/common/Dockerfile.
#
# The installer is pinned by version and verified by SHA-256. GitHub release
# assets are immutable, so a versioned URL plus a checksum means the script
# that runs is the script that was released.
###############################################################################
set -euo pipefail

SAFE_CHAIN_VERSION="${SAFE_CHAIN_VERSION:-1.5.18}"
SAFE_CHAIN_SHA256="${SAFE_CHAIN_SHA256:-bdbc58829853e598c09874fcc193f7cdb2a9a848875be45260a8b59bc4ce5439}"

INSTALLER="$(mktemp)"
trap 'rm -f "${INSTALLER}"' EXIT

curl -fsSL \
  "https://github.com/AikidoSec/safe-chain/releases/download/${SAFE_CHAIN_VERSION}/install-safe-chain.sh" \
  -o "${INSTALLER}"
echo "${SAFE_CHAIN_SHA256}  ${INSTALLER}" | sha256sum -c -

sh "${INSTALLER}" --ci

# The installer writes shims to ~/.safe-chain/shims. Put them ahead of the real
# package managers for the rest of this shell, and export them to the job where
# the CI platform supports it.
export PATH="${HOME}/.safe-chain/shims:${HOME}/.safe-chain/bin:${PATH}"

if [ -n "${GITHUB_PATH:-}" ]; then
  # GitHub Actions: persist for later steps.
  echo "${HOME}/.safe-chain/shims" >> "${GITHUB_PATH}"
  echo "${HOME}/.safe-chain/bin" >> "${GITHUB_PATH}"
elif [ -n "${AGENT_ID:-}" ]; then
  # Azure Pipelines: persist for later tasks.
  echo "##vso[task.prependpath]${HOME}/.safe-chain/shims"
  echo "##vso[task.prependpath]${HOME}/.safe-chain/bin"
fi
# GitLab CI runs every `script` line in one shell, so the export above is
# enough there.

safe-chain --version
