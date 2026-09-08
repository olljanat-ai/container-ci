#!/usr/bin/env bash
###############################################################################
# Log Docker in to Azure Container Registry using the identity the CI job has
# already authenticated as (workload identity federation via `az login`).
#
# Why not `az acr login`?
#   `az acr login` resolves the registry through the ARM control plane first,
#   which needs `Microsoft.ContainerRegistry/registries/read`. The pipeline
#   identities this repository creates deliberately hold data-plane repository
#   permissions only, so that call can fail with ResourceNotFound on a registry
#   they are perfectly entitled to push to.
#
#   The exchange below is the same one `az acr login` performs internally: swap
#   the Entra access token for an ACR refresh token, then use that as the
#   Docker password with the null-GUID username. It needs no control-plane
#   permission at all.
#
# Usage:
#   ./acr-login.sh <login-server>            # tenant from the current az context
#   ./acr-login.sh <login-server> <tenant-id>
#
# Requires: az (already logged in), curl, jq, docker.
###############################################################################
set -euo pipefail

REGISTRY="${1:?usage: acr-login.sh <login-server> [tenant-id]}"
TENANT_ID="${2:-$(az account show --query tenantId -o tsv)}"

echo "Requesting an Entra token for ${REGISTRY}..."
ACCESS_TOKEN="$(az account get-access-token \
  --resource "https://containerregistry.azure.net" \
  --query accessToken -o tsv)"

echo "Exchanging it for an ACR refresh token..."
REFRESH_TOKEN="$(curl -sS --fail-with-body -X POST \
  "https://${REGISTRY}/oauth2/exchange" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=access_token" \
  --data-urlencode "service=${REGISTRY}" \
  --data-urlencode "tenant=${TENANT_ID}" \
  --data-urlencode "access_token=${ACCESS_TOKEN}" \
  | jq -r '.refresh_token')"

if [ -z "${REFRESH_TOKEN}" ] || [ "${REFRESH_TOKEN}" = "null" ]; then
  echo "::error::Token exchange returned no refresh token for ${REGISTRY}" >&2
  exit 1
fi

# The null GUID is ACR's fixed username for Entra token authentication.
printf '%s' "${REFRESH_TOKEN}" \
  | docker login "${REGISTRY}" --username "00000000-0000-0000-0000-000000000000" --password-stdin

unset ACCESS_TOKEN REFRESH_TOKEN
echo "Logged in to ${REGISTRY}."
