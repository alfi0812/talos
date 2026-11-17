#!/usr/bin/env bash
# Checks that the Kubernetes version tuppr upgrades to is supported by the Talos version it
# upgrades to (both in upgradesettings.yaml). The supported range comes from the Talos source of
# that version: DefaultKubernetesVersion and SupportedKubernetesVersions (the number of minors
# supported from the default going backwards).
#
# Usage: talos_k8s_compat.sh   (from the repo root; needs yq and curl)
set -euo pipefail

SETTINGS="clusters/main/kubernetes/flux-system/flux/upgradesettings.yaml"
TALOS_VERSION="$(yq '.data.TALOS_VERSION' "$SETTINGS")"
KUBERNETES_VERSION="$(yq '.data.KUBERNETES_VERSION' "$SETTINGS")"

CONSTANTS="$(curl -fsSL "https://raw.githubusercontent.com/siderolabs/talos/${TALOS_VERSION}/pkg/machinery/constants/constants.go")"
DEFAULT="$(sed -nE 's/^\s*DefaultKubernetesVersion = "([0-9.]+)".*/\1/p' <<< "$CONSTANTS")"
SUPPORTED="$(sed -nE 's/^\s*SupportedKubernetesVersions = ([0-9]+).*/\1/p' <<< "$CONSTANTS")"
if [[ -z "$DEFAULT" || -z "$SUPPORTED" ]]; then
  echo "::error::Could not read the supported Kubernetes versions from the Talos ${TALOS_VERSION} source"
  exit 1
fi

minor() { local v="${1#v}"; v="${v#*.}"; echo "${v%%.*}"; }
major() { local v="${1#v}"; echo "${v%%.*}"; }

MAX_MINOR="$(minor "$DEFAULT")"
MIN_MINOR=$((MAX_MINOR - SUPPORTED + 1))
K8S_MAJOR="$(major "$KUBERNETES_VERSION")"
K8S_MINOR="$(minor "$KUBERNETES_VERSION")"
RANGE="$(major "$DEFAULT").${MIN_MINOR} – $(major "$DEFAULT").${MAX_MINOR}"

echo "Talos ${TALOS_VERSION} supports Kubernetes ${RANGE}; upgradesettings.yaml sets Kubernetes ${KUBERNETES_VERSION}"

if [[ "$K8S_MAJOR" != "$(major "$DEFAULT")" || "$K8S_MINOR" -lt "$MIN_MINOR" || "$K8S_MINOR" -gt "$MAX_MINOR" ]]; then
  result="❌ Kubernetes **${KUBERNETES_VERSION}** is not supported by Talos **${TALOS_VERSION}** (supports ${RANGE})."
  echo "::error file=${SETTINGS}::Kubernetes ${KUBERNETES_VERSION} is not supported by Talos ${TALOS_VERSION} (supports ${RANGE})"
  rc=1
else
  result="✅ Kubernetes **${KUBERNETES_VERSION}** is supported by Talos **${TALOS_VERSION}** (supports ${RANGE})."
  rc=0
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "## Talos / Kubernetes compatibility"; echo ""; echo "$result"; } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$rc"
