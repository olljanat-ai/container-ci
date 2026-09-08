# syntax=docker/dockerfile:1.11
###############################################################################
# Reference Dockerfile for the central registry pipelines (Node.js).
#
# The build stage installs Aikido Safe Chain before it installs any
# dependencies. Safe Chain proxies npm through Aikido Intel, so a package that
# is known malware - or that was published in the last 48 hours and has not
# been vetted yet - is blocked before it reaches the image. Installing it on
# the CI runner is not enough on its own: `npm ci` inside `docker build` runs
# in the build container, where the runner's shims do not exist.
#
# The runtime stage carries neither Safe Chain nor the build toolchain.
###############################################################################

# Base images come from the registry's pull-through cache so builds do not
# depend on Docker Hub's anonymous rate limit. REGISTRY is passed by the
# pipeline; the default keeps the file usable outside CI.
ARG REGISTRY=docker.io
ARG NODE_IMAGE=${REGISTRY}/cache/docker-hub/library/node:22-bookworm-slim

ARG SAFE_CHAIN_VERSION=1.5.18
ARG SAFE_CHAIN_SHA256=bdbc58829853e598c09874fcc193f7cdb2a9a848875be45260a8b59bc4ce5439

###############################################################################
# Stage 1 - dependencies and build, behind Safe Chain
###############################################################################
FROM ${NODE_IMAGE} AS build

ARG SAFE_CHAIN_VERSION
ARG SAFE_CHAIN_SHA256

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# `--ci` installs executable shims rather than shell aliases, which is what
# makes the interception work in a non-interactive RUN instruction.
RUN curl -fsSL "https://github.com/AikidoSec/safe-chain/releases/download/${SAFE_CHAIN_VERSION}/install-safe-chain.sh" -o /tmp/install-safe-chain.sh \
 && echo "${SAFE_CHAIN_SHA256}  /tmp/install-safe-chain.sh" | sha256sum -c - \
 && sh /tmp/install-safe-chain.sh --ci --install-dir /usr/local/safe-chain \
 && rm /tmp/install-safe-chain.sh

# The shims must precede the real npm on PATH.
ENV PATH="/usr/local/safe-chain/shims:/usr/local/safe-chain/bin:${PATH}"

# Fails the build if the shims are not actually in front of npm.
RUN npm safe-chain-verify

WORKDIR /app

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY . .
RUN npm run build --if-present \
 && npm prune --omit=dev

###############################################################################
# Stage 2 - runtime
###############################################################################
FROM ${NODE_IMAGE} AS runtime

ENV NODE_ENV=production

WORKDIR /app

COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/package.json ./package.json

USER node
EXPOSE 3000

# Trivy's misconfiguration scanner flags images that run as root or omit a
# healthcheck, so both are set here.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "dist/index.js"]
