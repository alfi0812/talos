#!/usr/bin/env bash
# Checks that the Kubernetes version tuppr upgrades to is supported by the Talos version it
# upgrades to (both in upgradesettings.yaml). The supported range comes from the Talos source of
# that version: DefaultKubernetesVersion and SupportedKubernetesVersions (the number of minors
# supported from the default going backwards).
#
# Optional environment:
#   BASE_SETTINGS     upgradesettings.yaml of the base branch, to show "old → new" in the report
#   TALOS_K8S_REPORT  path to write a Markdown report to (PR comment)
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
  compatible=false
  echo "::error file=${SETTINGS}::Kubernetes ${KUBERNETES_VERSION} is not supported by Talos ${TALOS_VERSION} (supports ${RANGE})"
else
  compatible=true
fi

# "old → new" when the base branch had a different version
change() {
  local old="$1" new="$2"
  if [[ -n "$old" && "$old" != "null" && "$old" != "$new" ]]; then
    echo "\`${old}\` → **\`${new}\`**"
  else
    echo "\`${new}\`"
  fi
}
BASE_TALOS=""
BASE_KUBERNETES=""
if [[ -n "${BASE_SETTINGS:-}" && -s "${BASE_SETTINGS}" ]]; then
  BASE_TALOS="$(yq '.data.TALOS_VERSION' "$BASE_SETTINGS")"
  BASE_KUBERNETES="$(yq '.data.KUBERNETES_VERSION' "$BASE_SETTINGS")"
fi

{
  echo "## 🐧 Talos / Kubernetes compatibility"
  echo ""
  if $compatible; then
    echo "✅ **Compatible**: Talos \`${TALOS_VERSION}\` supports Kubernetes \`${KUBERNETES_VERSION}\`."
  else
    echo "❌ **Not compatible**: Talos \`${TALOS_VERSION}\` does not support Kubernetes \`${KUBERNETES_VERSION}\`. **This PR can't be merged** until the versions in \`upgradesettings.yaml\` fit together."
  fi
  echo ""
  echo "| | Version |"
  echo "|---|---|"
  echo "| Talos | $(change "$BASE_TALOS" "$TALOS_VERSION") |"
  echo "| Kubernetes | $(change "$BASE_KUBERNETES" "$KUBERNETES_VERSION") |"
  echo "| Kubernetes supported by this Talos version | ${RANGE} |"
  echo ""
  echo "<sub>Supported range from the Talos ${TALOS_VERSION} source (\`DefaultKubernetesVersion\` ${DEFAULT}, \`SupportedKubernetesVersions\` ${SUPPORTED}).</sub>"
} > "${TALOS_K8S_REPORT:-/dev/null}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -n "${TALOS_K8S_REPORT:-}" ]]; then
  cat "$TALOS_K8S_REPORT" >> "$GITHUB_STEP_SUMMARY"
fi

$compatible
