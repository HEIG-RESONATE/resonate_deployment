#!/usr/bin/env bash
# Build and tag the three RESONATE images for publishing to GHCR.
#
# Run this yourself on the linux/amd64 build server, from the repo root, with
# submodules checked out (git clone --recurse-submodules). It builds and tags
# only; push commands are PRINTED at the end for you to run manually.
#
# Before pushing, log in to GHCR with a PAT that has write:packages:
#   docker login ghcr.io -u <github-username>
#   (paste the PAT when prompted for a password)
set -euo pipefail

cd "$(dirname "$0")"

REGISTRY=ghcr.io/heig-resonate

if ! git diff-index --quiet HEAD -- || [ -n "$(git status --porcelain)" ]; then
    echo "WARNING: working tree is not clean; the SHA tag will not describe what you built." >&2
fi

# The parent repo SHA pins both submodule revisions, so one tag identifies
# the exact source of all three images.
GIT_SHA=$(git rev-parse --short HEAD)

build() {
    local name=$1 context=$2
    echo "==> Building ${REGISTRY}/${name}:${GIT_SHA}"
    docker build \
        -t "${REGISTRY}/${name}:${GIT_SHA}" \
        -t "${REGISTRY}/${name}:latest" \
        "${context}"
}

build resonate-api      ./resonate2
build resonate-frontend ./resonate2/frontend
build resonate-agent    ./Chat-Agent

echo
echo "Built. To publish, run:"
for name in resonate-api resonate-frontend resonate-agent; do
    echo "  docker push ${REGISTRY}/${name}:${GIT_SHA}"
    echo "  docker push ${REGISTRY}/${name}:latest"
done
