#!/usr/bin/env bash
# Prints the Renovate version the cluster runs: the mend-renovate HelmRelease's chart version
# -> its appVersion (the Mend Renovate CE image) -> MEND_RNV_RENOVATE_VERSION in that image.
#
# Usage: renovate_version.sh   (from the repo root; needs helm, yq, jq and docker)
set -euo pipefail

HELMRELEASE="clusters/main/kubernetes/apps/renovate/app/helm-release.yaml"
CHART="$(yq '.spec.chart.spec.chart' "$HELMRELEASE")"
CHART_VERSION="$(yq '.spec.chart.spec.version' "$HELMRELEASE")"
REPO_NAME="$(yq '.spec.chart.spec.sourceRef.name' "$HELMRELEASE")"
REPO_URL="$(yq '.spec.url' "repositories/helm/${REPO_NAME}.yaml")"

APP_VERSION="$(helm show chart "${REPO_URL}/${CHART}" --version "$CHART_VERSION" 2>/dev/null | yq '.appVersion')"

# Image config without pulling the image (single- or multi-platform)
RENOVATE_VERSION="$(docker buildx imagetools inspect --format '{{json .Image}}' "ghcr.io/mend/renovate-ce:${APP_VERSION}" \
  | jq -r 'if has("config") then .config.Env[] else (to_entries[0].value.config.Env[]) end
           | select(startswith("MEND_RNV_RENOVATE_VERSION=")) | split("=")[1]')"

if [[ -z "$RENOVATE_VERSION" ]]; then
  echo "Could not find the Renovate version of ghcr.io/mend/renovate-ce:${APP_VERSION}" >&2
  exit 1
fi
echo "Mend Renovate CE ${APP_VERSION} (chart ${CHART}@${CHART_VERSION}) bundles Renovate ${RENOVATE_VERSION}" >&2
echo "$RENOVATE_VERSION"
