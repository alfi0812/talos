#!/usr/bin/env bash
# Renders a HelmRelease with `helm template`, without a cluster. Helm validates the values against
# the chart's own values.schema.json (TrueCharts: the schema of the common version the chart ships),
# so this catches invalid values before the slow install test.
#
# ${VAR} placeholders are substituted from the environment first (CI loads dummyEnv from
# ci/.config.yaml), unresolved ones stay literal. The CI values file (ci/<chart>.yaml) and the CI
# mutations of deploy_helmrelease.sh are NOT applied: this checks the values as they go to the cluster.
#
# Usage: template_helmrelease.sh <path/to/helm-release.yaml>
set -euo pipefail

HELMRELEASE_PATH="${1:-}"
if [[ -z "$HELMRELEASE_PATH" ]]; then
  echo "❌ No HelmRelease path provided"
  exit 1
fi

RELEASE_NAME="$(yq '.metadata.name' "$HELMRELEASE_PATH")"
NAMESPACE="$(yq '.metadata.namespace' "$HELMRELEASE_PATH")"
SOURCE_KIND="$(yq '.spec.chartRef.kind // .spec.chart.spec.sourceRef.kind' "$HELMRELEASE_PATH")"

case "$SOURCE_KIND" in
  HelmRepository)
    CHART_NAME="$(yq '.spec.chart.spec.chart' "$HELMRELEASE_PATH")"
    CHART_VERSION="$(yq '.spec.chart.spec.version' "$HELMRELEASE_PATH")"
    REPO_NAME="$(yq '.spec.chart.spec.sourceRef.name' "$HELMRELEASE_PATH")"
    REPO_URL="$(yq '.spec.url' "repositories/helm/${REPO_NAME}.yaml")"
    if [[ "$REPO_URL" == oci://* ]]; then
      CHART_REF="$REPO_URL/$CHART_NAME"
    else
      helm repo add "$REPO_NAME" "$REPO_URL" >/dev/null 2>&1 || true
      helm repo update "$REPO_NAME" >/dev/null 2>&1
      CHART_REF="$REPO_NAME/$CHART_NAME"
    fi
    ;;
  OCIRepository)
    REPO_NAME="$(yq '.spec.chartRef.name' "$HELMRELEASE_PATH")"
    REPO_FILE="repositories/oci/${REPO_NAME}.yaml"
    CHART_REF="$(yq '.spec.url' "$REPO_FILE")"
    CHART_VERSION="$(yq '.spec.ref.tag' "$REPO_FILE")"
    ;;
  *)
    echo "❌ Unsupported chart source kind: $SOURCE_KIND"
    exit 1
    ;;
esac

echo "📦 Chart:     $CHART_REF@$CHART_VERSION"
echo "🏷️ Release:   $RELEASE_NAME ($NAMESPACE)"

# Substitute only the ${VAR}s that are set, unresolved ones stay literal
VALUES_FILE="$(mktemp)"
trap 'rm -f "$VALUES_FILE"' EXIT
yq '.spec.values // {}' "$HELMRELEASE_PATH" > "$VALUES_FILE.raw"
EXISTING_VARS=""
MISSING_VARS=""
while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  if printenv "${var:2:-1}" >/dev/null 2>&1; then
    EXISTING_VARS+="${var} "
  else
    MISSING_VARS+="${var} "
  fi
done <<< "$(grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' "$VALUES_FILE.raw" | sort -u || true)"
envsubst "$EXISTING_VARS" < "$VALUES_FILE.raw" > "$VALUES_FILE"
rm -f "$VALUES_FILE.raw"

if [[ -n "$MISSING_VARS" ]]; then
  echo "⚠️ Unresolved variables (kept as-is, add them to dummyEnv in ci/.config.yaml if they cause errors):"
  printf '     • %s\n' $MISSING_VARS
fi

if helm template "$RELEASE_NAME" "$CHART_REF" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" > /dev/null; then
  echo "✅ $HELMRELEASE_PATH renders and its values match the chart schema"
else
  echo "❌ helm template failed for $HELMRELEASE_PATH"
  exit 1
fi
