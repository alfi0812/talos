#!/usr/bin/env bash
# Installs the Flux CLI in the version the cluster runs (the flux-manifests OCIRepository tag)
# into ~/.local/bin and adds it to the GitHub Actions PATH.
set -euo pipefail

FLUX_VERSION="$(yq '.spec.ref.tag' repositories/oci/flux-manifests.yaml)"
bin="$HOME/.local/bin"
mkdir -p "$bin"

echo "Installing Flux CLI ${FLUX_VERSION} (the cluster's Flux version)"
curl -fsSL "https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION#v}_linux_amd64.tar.gz" \
  | tar xz -C "$bin" flux

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$bin" >> "$GITHUB_PATH"
fi
"$bin/flux" version --client
