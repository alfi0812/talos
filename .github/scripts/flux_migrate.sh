#!/usr/bin/env bash
# Migrates the Flux objects in clusters/ and repositories/ to the latest API versions of the
# cluster's Flux version (flux migrate), and points the "# yaml-language-server" schema comment
# above each migrated object to the schema of its new API version.
#
# Usage: flux_migrate.sh   (from the repo root; needs flux in the cluster's version, yq and perl)
set -euo pipefail

FLUX_VERSION="$(yq '.spec.ref.tag' repositories/oci/flux-manifests.yaml)"
FLUX_MINOR="${FLUX_VERSION#v}"
FLUX_MINOR="${FLUX_MINOR%.*}"
echo "=== Migrating to the latest API versions of Flux ${FLUX_MINOR} ==="

for dir in clusters repositories; do
  flux migrate -f "$dir" --version "$FLUX_MINOR" --yes
done

# Keep the schema comments in step: "...home-operations.com/<group>/<kind>_<old>.json" directly
# above "apiVersion: <group>/<new>" becomes "<kind>_<new>.json"
find clusters repositories -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
  | xargs -0 perl -0pi -e 's{(\$schema=https://k8s-schemas\.home-operations\.com/([^/\s]+)/[a-z0-9]+_)[a-z0-9]+(\.json\napiVersion: \2/)([a-z0-9]+)\n}{$1$4$3$4\n}g'
