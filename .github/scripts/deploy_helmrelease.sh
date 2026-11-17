#!/usr/bin/env bash
set -euo pipefail

HELMRELEASE_PATH="${1:-}"

# --------------------------------------------------
# Colors & Formatting
# --------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # reset

# --------------------------------------------------
# Logging Functions
# --------------------------------------------------
print_header() {
  echo -e "${BOLD}$(printf '═%.0s' {1..78})${NC}"
  echo -e "${BLUE}${BOLD}$2  $1  $2${NC}"
  echo -e "${BOLD}$(printf '═%.0s' {1..78})${NC}"
}

print_section() {
  echo " "
  echo -e "${BLUE}${BOLD}$1${NC}"
  echo -e "${DIM}$(printf '─%.0s' {1..78})${NC}"
}

print_sub_section() {
  echo -e "${BLUE}$1${NC}"
}

# --------------------------------------------------
# Chart and dependency helpers
# --------------------------------------------------

# Resolves the chart of a HelmRelease (chart.spec + HelmRepository, or
# chartRef + OCIRepository). Sets RESOLVED_CHART_NAME, RESOLVED_CHART_VERSION,
# RESOLVED_CHART_REF and RESOLVED_REPO_URL.
resolve_helm_chart() {
  local helmrelease_path="$1"
  local chart_ref_kind chart_name source_name source_file source_url

  if [[ ! -f "$helmrelease_path" ]]; then
    echo "❌ HelmRelease not found: $helmrelease_path"
    return 1
  fi

  if [[ -n "$(yq -r '.spec.chartRef.name // ""' "$helmrelease_path")" ]]; then
    chart_ref_kind="$(yq -r '.spec.chartRef.kind // ""' "$helmrelease_path")"
    source_name="$(yq -r '.spec.chartRef.name' "$helmrelease_path")"
    source_file="repositories/oci/${source_name}.yaml"

    if [[ "$chart_ref_kind" != "OCIRepository" ]]; then
      echo "❌ Unsupported chartRef kind '${chart_ref_kind}': $helmrelease_path"
      return 1
    fi
    if [[ ! -f "$source_file" ]]; then
      echo "❌ OCIRepository not found: $source_file"
      return 1
    fi

    RESOLVED_CHART_NAME="$source_name"
    RESOLVED_CHART_REF="$(yq -r '.spec.url // ""' "$source_file")"
    RESOLVED_CHART_VERSION="$(yq -r '.spec.ref.tag // ""' "$source_file")"
    RESOLVED_REPO_URL="$RESOLVED_CHART_REF"
  else
    chart_name="$(yq -r '.spec.chart.spec.chart // ""' "$helmrelease_path")"
    source_name="$(yq -r '.spec.chart.spec.sourceRef.name // ""' "$helmrelease_path")"
    source_file="repositories/helm/${source_name}.yaml"
    RESOLVED_CHART_VERSION="$(yq -r '.spec.chart.spec.version // ""' "$helmrelease_path")"

    if [[ -z "$chart_name" || -z "$source_name" || ! -f "$source_file" ]]; then
      echo "❌ Unable to resolve chart from: $helmrelease_path"
      return 1
    fi

    source_url="$(yq -r '.spec.url' "$source_file")"
    RESOLVED_CHART_NAME="$chart_name"
    RESOLVED_REPO_URL="$source_url"
    if [[ "$source_url" == oci://* ]]; then
      RESOLVED_CHART_REF="${source_url}/${chart_name}"
    else
      helm repo add "$source_name" "$source_url" --force-update >/dev/null
      RESOLVED_CHART_REF="${source_name}/${chart_name}"
    fi
  fi

  if [[ -z "$RESOLVED_CHART_REF" || -z "$RESOLVED_CHART_VERSION" ]]; then
    echo "❌ Chart reference or version is empty: $helmrelease_path"
    return 1
  fi
}

# Writes the values of a HelmRelease to a file, with the ${VARS} that are set
# in the environment substituted. Missing ones stay literal ${VAR}.
# Sets EXISTING_VARS and MISSING_VARS.
extract_values() {
  local helmrelease_path="$1" out="$2"
  local raw vars var name
  raw="$(mktemp)"
  yq '.spec.values // {}' "$helmrelease_path" > "$raw"

  vars="$(grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' "$raw" | sort -u || true)"
  EXISTING_VARS=""
  MISSING_VARS=""
  while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    name="${var:2:-1}"  # strip ${ and }
    if printenv "$name" >/dev/null 2>&1; then
      EXISTING_VARS+="${var} "
    else
      MISSING_VARS+="${var} "
    fi
  done <<< "$vars"

  envsubst "$EXISTING_VARS" < "$raw" > "$out"
}

# True if the rendered chart contains a resource of the API group (and kind, if given)
rendered_uses() {
  API_GROUP="$1" API_KIND="${2:-}" yq ea -e '
    select(
      ((.apiVersion // "") | split("/") | .[0]) == strenv(API_GROUP)
      and (strenv(API_KIND) == "" or .kind == strenv(API_KIND))
    )
  ' "$RENDERED" >/dev/null 2>&1
}

# Applies the CRDs of a dependency, rendered from the chart and values of its
# HelmRelease, and waits until they are Established. CRDs that the chart under
# test renders itself are skipped (helm would refuse to adopt them).
install_dependency_crds() {
  local name="$1" icon="$2" helmrelease_path="$3"
  local values rendered_crds own_crds crd_count

  resolve_helm_chart "$helmrelease_path"
  values="$(mktemp)"
  rendered_crds="$(mktemp)"
  extract_values "$helmrelease_path" "$values"
  own_crds="$(yq ea -N -r 'select(.kind == "CustomResourceDefinition") | .metadata.name' "$RENDERED" | tr '\n' ' ')"

  echo "::group::${icon} Installing ${name} CRDs (${RESOLVED_CHART_VERSION})..."
  helm template "ci-${name}" "$RESOLVED_CHART_REF" \
    --version "$RESOLVED_CHART_VERSION" \
    --include-crds \
    --no-hooks \
    --values "$values" \
  | OWN_CRDS="$own_crds" yq ea '
      select(.kind == "CustomResourceDefinition")
      | select(.metadata.name as $n | strenv(OWN_CRDS) | split(" ") | any_c(. == $n) | not)
    ' > "$rendered_crds"

  crd_count="$(yq ea -N -r 'select(.kind == "CustomResourceDefinition") | .metadata.name' "$rendered_crds" | grep -c . || true)"
  if [[ "$crd_count" -eq 0 ]]; then
    if [[ -n "$own_crds" ]]; then
      echo "${icon} ${name} CRDs are rendered by the chart under test, skipping"
      echo "::endgroup::"
      return 0
    fi
    echo "❌ No CRDs rendered for ${name}"
    return 1
  fi

  kubectl apply --server-side --force-conflicts --filename "$rendered_crds"
  kubectl wait --for=condition=Established --timeout=120s --filename "$rendered_crds"
  echo "${icon} Installed ${crd_count} ${name} CRD(s)"
  echo "::endgroup::"
}

# --------------------------------------------------
# Check Helmrelease Path
# --------------------------------------------------

if [[ -z "$HELMRELEASE_PATH" ]]; then
  echo "❌ No HelmRelease path provided"
  exit 1
fi

# --------------------------------------------------
# Check stopAll
# --------------------------------------------------
# STOP_ALL=$(yq '.spec.values.global.stopAll // "false"' "$HELMRELEASE_PATH")
#
# if [[ "$STOP_ALL" == "true" ]]; then
#   echo -e "${YELLOW}⏭  ${BOLD}DEPLOYMENT SKIPPED  ⏭${NC}"
#   echo -e "${YELLOW}Reason:  global.stopAll=true${NC}"
#   exit 0
# fi

# --------------------------------------------------
# Extract HelmRelease metadata
# --------------------------------------------------
RELEASE_NAME="$(yq '.metadata.name' "$HELMRELEASE_PATH")"
NAMESPACE="$(yq '.metadata.namespace' "$HELMRELEASE_PATH")"
resolve_helm_chart "$HELMRELEASE_PATH"
CHART_NAME="$RESOLVED_CHART_NAME"
CHART_VERSION="$RESOLVED_CHART_VERSION"
CHART_REF="$RESOLVED_CHART_REF"
REPO_URL="$RESOLVED_REPO_URL"
CI_VALUES_FILE="ci/$CHART_NAME.yaml"

print_header "HelmRelease Deployment Test by Alfi0812" "⌛"

print_section "⚙️ Processing: $HELMRELEASE_PATH"

echo "📦 Chart:         $CHART_NAME@$CHART_VERSION"
echo "🌍 Repository:    $REPO_URL"
echo "🏷️ Release Name:  $RELEASE_NAME"
echo "📂 Namespace:     $NAMESPACE"


# --------------------------------------------------
# Environment Variable substitution
# --------------------------------------------------
print_section "🧬 Values Manipulation for CI Testing"

print_sub_section "🔄 Environment Variable substitution"
VALUES_FILE="$(mktemp)"
extract_values "$HELMRELEASE_PATH" "$VALUES_FILE"

# Summary of substitutions for logging
replaced_count=$(wc -w <<< "$EXISTING_VARS")
missing_count=$(wc -w <<< "$MISSING_VARS")

if [[ "$replaced_count" -gt 0 ]]; then
  echo -e "${GREEN}      ✔ Replaced variables:${NC}"
  printf '        • %s\n' $EXISTING_VARS
else
  echo -e "${GREEN}      ✔ Replaced variables: none${NC}"
fi

if [[ "$missing_count" -gt 0 ]]; then
  echo -e "${YELLOW}      ⚠ Unresolved variables (kept as-is):${NC}"
  printf '        • %s\n' $MISSING_VARS
else
  echo -e "${GREEN}      ✔ No unresolved variables${NC}"
fi

# --------------------------------------------------
# Change PVC and CNPG because of backup restore issues
# --------------------------------------------------
print_sub_section "🔄 CI value mutations"
changed=false

# Disable volsync
if yq -e '
  (.. | select(type == "!!map" and has("volsync")).volsync[]?.src.enabled == true) or
  (.. | select(type == "!!map" and has("volsync")).volsync[]?.dest.enabled == true)
' "$VALUES_FILE" >/dev/null 2>&1; then

  yq -i '
    (.. | select(type == "!!map" and has("volsync")).volsync[]?.src.enabled) = false |
    (.. | select(type == "!!map" and has("volsync")).volsync[]?.dest.enabled) = false
  ' "$VALUES_FILE"

  echo "      ⚠️ Volsync src/dest disabled for CI"
  changed=true
fi

# Remove unsupported persistence entries (nfs + existingClaim)
if yq -e '
  (.persistence? // {})
  | to_entries[]
  | select(
      .value.type? == "nfs"
      or (.value.existingClaim? != null)
    )
' "$VALUES_FILE" >/dev/null 2>&1; then

  yq -i '
    .persistence |= with_entries(
      select(
        .value.type? != "nfs"
        and (.value.existingClaim? == null)
      )
    ) |
    del(.persistence | select(. == {}))
  ' "$VALUES_FILE"

  echo "      ⚠️ Unsupported persistence removed for CI"
  changed=true
fi

# CNPG: keep the cluster (apps reference its secrets, e.g. cnpg-main-urls), but drop
# backup/restore: CI has no S3, so start every database empty in standalone mode
if yq -e '(.cnpg // {}) | to_entries[] | select(.value.backups != null or .value.recovery != null or .value.mode == "recovery")' "$VALUES_FILE" >/dev/null 2>&1; then
  yq -i '
    .cnpg |= with_entries(
      .value |= (
        del(.backups) | del(.recovery)
        | (select(.mode == "recovery") | .mode) = "standalone"
      )
    )
  ' "$VALUES_FILE"
  echo "      ⚠️ CNPG backups/recovery removed, mode set to standalone for CI"
  changed=true
fi

# Force global.stopAll=false
if yq -e '.global.stopAll == true' "$VALUES_FILE" >/dev/null 2>&1; then
  yq -i '.global.stopAll = false' "$VALUES_FILE"
  echo "      ⚠️ global.stopAll forced to false"
  changed=true
fi

if [ "$changed" = false ]; then
  echo "      ℹ️ No CI mutations needed"
fi

# --------------------------------------------------
# Value Dump for debugging
# --------------------------------------------------
print_sub_section "📄 Final values used for deploying"
echo "::group::    🧩 Rendered Helm values:"
echo -e "${BOLD}${BLUE}📄 values.yaml (after CI patches)${NC}"
yq -P '.' "$VALUES_FILE"
echo " "
echo "::endgroup::"

# --------------------------------------------------
# CI Values file check
# --------------------------------------------------
HELM_VALUES_ARGS=(--values "$VALUES_FILE")

if [[ -f "$CI_VALUES_FILE" ]]; then
  echo "::group::    🧪 Used CI values:"
  echo -e "${BOLD}${BLUE}📄 $CI_VALUES_FILE${NC}"
  yq -P '.' "$CI_VALUES_FILE"
  echo " "
  echo "::endgroup::"

  HELM_VALUES_ARGS+=(--values "$CI_VALUES_FILE")
fi

# --------------------------------------------------
# Render manifests for dependency detection
# --------------------------------------------------
print_section "🔧 Installing dependencies"

RENDERED="$(mktemp)"

if ! helm template "$RELEASE_NAME" "$CHART_REF" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  "${HELM_VALUES_ARGS[@]}" \
  > "$RENDERED" 2> "$RENDERED.err"; then
  echo "❌ helm template failed:"
  cat "$RENDERED.err"
  exit 1
fi

# --------------------------------------------------
# Detect dependencies
# --------------------------------------------------
install_cnpg=false
install_volsync=false
install_ingress=false
install_certmanager=false
install_prometheus=false
install_metallb=false
install_intel_crds=false
install_nfd_crds=false

# Match on the apiVersion group of rendered resources, so annotations such as
# cert-manager.io/cluster-issuer don't count as a dependency
rendered_uses "postgresql.cnpg.io" && install_cnpg=true
# rendered_uses "volsync.backube" && install_volsync=true
rendered_uses "networking.k8s.io" "Ingress" && install_ingress=true
rendered_uses "cert-manager.io" && install_certmanager=true
rendered_uses "monitoring.coreos.com" && install_prometheus=true
rendered_uses "metallb.io" && install_metallb=true
rendered_uses "deviceplugin.intel.com" && install_intel_crds=true
rendered_uses "nfd.k8s-sigs.io" && install_nfd_crds=true

echo "🔎 Dependencies:"
echo "     CNPG:        $install_cnpg"
# echo "     VolSync:     $install_volsync"
echo "     Ingress:     $install_ingress"
echo "     CertManager: $install_certmanager"
echo "     Prometheus:  $install_prometheus"
echo "     MetalLB:     $install_metallb"
echo "     Intel CRDs:  $install_intel_crds"
echo "     NFD CRDs:    $install_nfd_crds"

# --------------------------------------------------
# Install dependencies
# --------------------------------------------------
# Chart and version come from the dependency's own HelmRelease, so CI follows
# what the cluster runs. Only CNPG and ingress-nginx need a running controller,
# everything else only needs its CRDs.

if $install_cnpg; then
  resolve_helm_chart clusters/main/kubernetes/system/cloudnative-pg/app/helm-release.yaml
  echo "::group::🗄️ Installing CloudNativePG (${RESOLVED_CHART_VERSION})..."
  helm install cloudnative-pg "$RESOLVED_CHART_REF" \
    --version "$RESOLVED_CHART_VERSION" \
    --namespace cloudnative-pg \
    --create-namespace \
    --wait \
    --timeout 5m
  echo "🗄️ Done installing CloudNativePG"
  echo "::endgroup::"
fi

if $install_volsync; then
  echo "::group::💾 Installing VolSync CRDs..."
  kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationsources.yaml
  kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationdestinations.yaml
  echo "💾 Done installing Volsync CRDs"
  echo "::endgroup::"
fi

if $install_ingress; then
  resolve_helm_chart clusters/main/kubernetes/networking/nginx-internal/app/helm-release.yaml
  echo "::group::🌐 Installing ingress-nginx (${RESOLVED_CHART_VERSION})..."
  helm install ingress-nginx "$RESOLVED_CHART_REF" \
    --version "$RESOLVED_CHART_VERSION" \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.ingressClassResource.default=true \
    --set controller.publishService.enabled=false \
    --set controller.service.type="ClusterIP" \
    --set controller.config.allow-snippet-annotations=true \
    --set controller.config.annotations-risk-level="Critical" \
    --wait \
    --timeout 5m
  echo "🌐 Done installing ingress-nginx"
  echo "::endgroup::"
fi

if $install_certmanager; then
  install_dependency_crds "cert-manager" "🔐" \
    clusters/main/kubernetes/system/cert-manager/app/helm-release.yaml
fi

if $install_prometheus; then
  install_dependency_crds "kube-prometheus-stack" "📊" \
    clusters/main/kubernetes/observability/kube-prometheus-stack/app/helm-release.yaml
fi

if $install_metallb; then
  # The MetalLB CRDs reference the webhook service in this namespace
  kubectl create namespace metallb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  install_dependency_crds "metallb" "📡" \
    clusters/main/kubernetes/system/metallb/app/helm-release.yaml
fi

if $install_intel_crds; then
  install_dependency_crds "intel-device-plugins-operator" "🧩" \
    clusters/main/kubernetes/system/intel-device-plugin-operator/app/helm-release.yaml
fi

if $install_nfd_crds; then
  install_dependency_crds "node-feature-discovery" "🏷️" \
    clusters/main/kubernetes/kube-system/node-feature-discovery/app/helm-release.yaml
fi

# --------------------------------------------------
# Dummy secrets for values that reference Secrets outside the chart
# (expandObjectName: false, e.g. SOPS-encrypted oidc.secret.yaml)
# --------------------------------------------------
EXTERNAL_SECRETS="$(yq -o=json '[.. | select(type == "!!map" and has("secretKeyRef")) | .secretKeyRef | select(.expandObjectName == false) | {"name": .name, "key": .key}]' "$VALUES_FILE")"

if [[ "$(jq 'length' <<< "$EXTERNAL_SECRETS")" -gt 0 ]]; then
  print_section "🔑 Creating dummy external secrets"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  for name in $(jq -r '.[].name' <<< "$EXTERNAL_SECRETS" | sort -u); do
    args=()
    for key in $(jq -r --arg n "$name" '.[] | select(.name == $n) | .key' <<< "$EXTERNAL_SECRETS" | sort -u); do
      args+=(--from-literal="$key=ci-dummy-value")
    done
    kubectl -n "$NAMESPACE" create secret generic "$name" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "      🔑 $name (${#args[@]} key(s))"
  done
fi

# --------------------------------------------------
# Deploy chart
# --------------------------------------------------
print_section "🚀 Deploying $RELEASE_NAME..."

set +e
helm upgrade --install "$RELEASE_NAME" "$CHART_REF" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  "${HELM_VALUES_ARGS[@]}" \
  --skip-crds \
  --wait \
  --timeout 5m
HELM_RC=$?
set -e

# --------------------------------------------------
# Debug info
# --------------------------------------------------
print_section "🐛 Debug info"
print_section "📦 Pods:"
kubectl get pods -n "$NAMESPACE" -o wide || true

print_section "📅 Events:"
kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp || true

for pod in $(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null); do
  print_section "📜 Logs for $pod:"
  kubectl logs -n "$NAMESPACE" "$pod" --all-containers --tail=200 || true
done

# --------------------------------------------------
# Exit result
# --------------------------------------------------
print_section "🎯 Result"
if [ "$HELM_RC" -ne 0 ]; then
  echo "❌ Deployment failed"
  exit "$HELM_RC"
fi

echo "✅ Deployment succeeded"
