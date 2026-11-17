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

# Substitutes the ${VARS} that are set in the environment, like Flux does with
# the cluster variables. Missing ones stay literal ${VAR}.
# Sets EXISTING_VARS and MISSING_VARS.
substitute_vars() {
  local in="$1" out="$2"
  local vars var name
  vars="$(grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' "$in" | sort -u || true)"
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

  envsubst "$EXISTING_VARS" < "$in" > "$out"
}

# Writes the values of a HelmRelease to a file, with ${VARS} substituted.
extract_values() {
  local helmrelease_path="$1" out="$2"
  local raw
  raw="$(mktemp)"
  yq '.spec.values // {}' "$helmrelease_path" > "$raw"
  substitute_vars "$raw" "$out"
}

# True if the rendered chart or the app's other manifests contain a resource of
# the API group (and kind, if given)
rendered_uses() {
  local files=("$RENDERED")
  [[ -n "${EXTRAS:-}" && -s "${EXTRAS:-}" ]] && files+=("$EXTRAS")
  API_GROUP="$1" API_KIND="${2:-}" yq ea -e '
    select(
      ((.apiVersion // "") | split("/") | .[0]) == strenv(API_GROUP)
      and (strenv(API_KIND) == "" or .kind == strenv(API_KIND))
    )
  ' "${files[@]}" >/dev/null 2>&1
}

# Builds the app folder (kustomization.yaml next to the HelmRelease) into
# EXTRAS: everything Flux applies besides the HelmRelease, with ${VARS}
# substituted. SOPS-encrypted files and Flux objects (no Flux in CI) are left out.
build_app_manifests() {
  local app_dir raw
  app_dir="$(dirname "$HELMRELEASE_PATH")"
  EXTRAS="$(mktemp)"
  [[ -f "$app_dir/kustomization.yaml" ]] || return 0

  raw="$(mktemp)"
  if ! kubectl kustomize "$app_dir" > "$raw" 2> "$raw.err"; then
    echo "❌ kustomize build failed: $app_dir"
    cat "$raw.err"
    return 1
  fi
  substitute_vars "$raw" "$raw.sub"
  yq ea '
    select(
      .kind != "HelmRelease"
      and .sops == null
      and ((.apiVersion // "") | test("\.toolkit\.fluxcd\.io/") | not)
    )
  ' "$raw.sub" > "$EXTRAS"
}

# Turns spec.valuesFrom into --values files (VALUES_FROM_ARGS), in order, so
# the inline values still win like in Flux. Only ConfigMaps from the app folder
# can be read; Secrets are SOPS-encrypted.
resolve_values_from() {
  local count i kind name key target file
  VALUES_FROM_ARGS=()
  count="$(yq '.spec.valuesFrom // [] | length' "$HELMRELEASE_PATH")"
  for ((i = 0; i < count; i++)); do
    kind="$(yq -r ".spec.valuesFrom[$i].kind" "$HELMRELEASE_PATH")"
    name="$(yq -r ".spec.valuesFrom[$i].name" "$HELMRELEASE_PATH")"
    key="$(yq -r ".spec.valuesFrom[$i].valuesKey // \"values.yaml\"" "$HELMRELEASE_PATH")"
    target="$(yq -r ".spec.valuesFrom[$i].targetPath // \"\"" "$HELMRELEASE_PATH")"

    if [[ -n "$target" ]]; then
      echo -e "${YELLOW}      ⚠ valuesFrom ${kind}/${name}: targetPath is not supported in CI, skipped${NC}"
      continue
    fi

    file="$(mktemp)"
    KIND="$kind" NAME="$name" KEY="$key" yq ea -N -r '
      select(.kind == strenv(KIND) and .metadata.name == strenv(NAME)) | .data[strenv(KEY)] // ""
    ' "$EXTRAS" > "$file"

    if [[ ! -s "$file" ]] || [[ "$(tr -d '[:space:]' < "$file")" == "" ]]; then
      echo -e "${YELLOW}      ⚠ valuesFrom ${kind}/${name} (${key}): not found in the app folder, skipped${NC}"
      continue
    fi
    echo -e "${GREEN}      ✔ valuesFrom ${kind}/${name} (${key})${NC}"
    VALUES_FROM_ARGS+=(--values "$file")
  done
}

# Runs spec.postRenderers (kustomize patches and images) through a Helm 4
# post-renderer plugin in a temporary plugin folder. Sets POST_RENDER_ARGS.
setup_post_renderer() {
  local dir
  POST_RENDER_ARGS=()
  [[ "$(yq '.spec.postRenderers // [] | length' "$HELMRELEASE_PATH")" -gt 0 ]] || return 0

  dir="$(mktemp -d)"
  mkdir -p "$dir/plugins/ci-kustomize"
  cat > "$dir/plugins/ci-kustomize/plugin.yaml" <<'PLUGIN'
apiVersion: v1
type: postrenderer/v1
name: ci-kustomize
version: 0.1.0
runtime: subprocess
runtimeConfig:
  platformCommand:
    - command: ${HELM_PLUGIN_DIR}/run.sh
PLUGIN
  cat > "$dir/plugins/ci-kustomize/run.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
d="$(mktemp -d)"
cat > "$d/all.yaml"
cp "${CI_POSTRENDER_KUSTOMIZATION:?}" "$d/kustomization.yaml"
kubectl kustomize "$d"
RUN
  chmod +x "$dir/plugins/ci-kustomize/run.sh"

  substitute_vars "$HELMRELEASE_PATH" "$dir/helm-release.yaml"
  yq '{
    "apiVersion": "kustomize.config.k8s.io/v1beta1",
    "kind": "Kustomization",
    "resources": ["all.yaml"],
    "patches": [.spec.postRenderers[].kustomize.patches[]?],
    "images": [.spec.postRenderers[].kustomize.images[]?]
  } | del(.patches | select(length == 0)) | del(.images | select(length == 0))
  ' "$dir/helm-release.yaml" > "$dir/kustomization.yaml"

  export HELM_PLUGINS="$dir/plugins"
  export CI_POSTRENDER_KUSTOMIZATION="$dir/kustomization.yaml"
  POST_RENDER_ARGS=(--post-renderer ci-kustomize)
  echo -e "${GREEN}      ✔ postRenderers applied with kustomize${NC}"
}

# Applies EXTRAS. Kinds the CI cluster doesn't serve are skipped with a warning.
apply_app_manifests() {
  local served kept skipped
  [[ -s "$EXTRAS" ]] || return 0
  print_section "📎 Applying the app's other manifests"

  # "group|kind" of every served resource (core group is empty)
  served="$(kubectl api-resources --no-headers | awk '{v=$(NF-2); i=index(v,"/"); print (i ? substr(v,1,i-1) : "") "|" $NF}')"
  kept="$(mktemp)"
  skipped="$(mktemp)"
  # Per document (yq e): "group|kind", the version stripped from apiVersion
  local key='(.apiVersion | sub("/?[^/]*$"; "")) + "|" + .kind'
  SERVED="$served" yq e "select(${key} as \$k | strenv(SERVED) | split(\"\n\") | any_c(. == \$k))" "$EXTRAS" > "$kept"
  SERVED="$served" yq e -N -r "select(${key} as \$k | strenv(SERVED) | split(\"\n\") | any_c(. == \$k) | not) | .kind + \"/\" + .metadata.name" "$EXTRAS" > "$skipped"

  while IFS= read -r res; do
    [[ -n "$res" ]] && echo -e "${YELLOW}      ⚠ $res: kind not served in CI, skipped${NC}"
  done < "$skipped"

  if [[ -s "$kept" ]]; then
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side -n "$NAMESPACE" -f "$kept"
  fi
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
# App folder, valuesFrom and postRenderers
# --------------------------------------------------
print_sub_section "📎 App folder, valuesFrom and postRenderers"
build_app_manifests
resolve_values_from
setup_post_renderer

# --------------------------------------------------
# CI Values file check
# --------------------------------------------------
HELM_VALUES_ARGS=("${VALUES_FROM_ARGS[@]}" --values "$VALUES_FILE")

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
  "${POST_RENDER_ARGS[@]}" \
  > "$RENDERED" 2> "$RENDERED.err"; then
  echo "❌ helm template failed:"
  cat "$RENDERED.err"
  exit 1
fi

# --------------------------------------------------
# Detect dependencies
# --------------------------------------------------
install_cnpg=false
install_ingress=false
install_certmanager=false
install_prometheus=false
install_metallb=false
install_intel_crds=false
install_nfd_crds=false

# Match on the apiVersion group of rendered resources (chart and app folder), so
# annotations such as cert-manager.io/cluster-issuer don't count as a dependency
rendered_uses "postgresql.cnpg.io" && install_cnpg=true
rendered_uses "networking.k8s.io" "Ingress" && install_ingress=true
rendered_uses "cert-manager.io" && install_certmanager=true
rendered_uses "monitoring.coreos.com" && install_prometheus=true
rendered_uses "metallb.io" && install_metallb=true
rendered_uses "deviceplugin.intel.com" && install_intel_crds=true
rendered_uses "nfd.k8s-sigs.io" && install_nfd_crds=true

echo "🔎 Dependencies:"
echo "     CNPG:        $install_cnpg"
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

# Namespaces whose pods and logs are shown when the test fails
DEBUG_NAMESPACES=()

if $install_cnpg; then
  DEBUG_NAMESPACES+=(cloudnative-pg)
  resolve_helm_chart clusters/main/kubernetes/system/cloudnative-pg/app/helm-release.yaml
  echo "::group::🗄️ Installing CloudNativePG (${RESOLVED_CHART_VERSION})..."
  # The whole operator, not just CRDs: it has to create the database pods
  helm install cloudnative-pg "$RESOLVED_CHART_REF" \
    --version "$RESOLVED_CHART_VERSION" \
    --namespace cloudnative-pg \
    --create-namespace \
    --set crds.create=true \
    --set monitoring.podMonitorEnabled=false \
    --set monitoring.grafanaDashboard.create=false \
    --wait \
    --timeout 5m
  echo "🗄️ Done installing CloudNativePG"
  echo "::endgroup::"
fi

if $install_ingress; then
  DEBUG_NAMESPACES+=(ingress-nginx)
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
# App folder manifests (PrometheusRules, RBAC, ConfigMaps, ...)
# --------------------------------------------------
apply_app_manifests

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
  "${POST_RENDER_ARGS[@]}" \
  --skip-crds \
  --wait \
  --timeout 5m
HELM_RC=$?
set -e

# --------------------------------------------------
# CNPG clusters: helm --wait doesn't wait for them
# --------------------------------------------------
DB_RC=0
if [[ "$HELM_RC" -eq 0 ]] && rendered_uses "postgresql.cnpg.io" "Cluster"; then
  print_section "🗄️ Waiting for CNPG clusters"
  kubectl wait clusters.postgresql.cnpg.io --all -n "$NAMESPACE" \
    --for=condition=Ready --timeout=5m || DB_RC=1
  kubectl get clusters.postgresql.cnpg.io -n "$NAMESPACE" || true
fi

# --------------------------------------------------
# Debug info
# --------------------------------------------------
debug_namespace() {
  local ns="$1" pod ready phase restarts
  print_section "🐛 Debug info: $ns"
  print_sub_section "📦 Pods:"
  kubectl get pods -n "$ns" -o wide || true

  print_sub_section "📅 Events:"
  kubectl get events -n "$ns" --sort-by=.metadata.creationTimestamp || true

  for pod in $(kubectl get pods -n "$ns" -o name 2>/dev/null); do
    print_sub_section "📜 Logs for $pod:"
    kubectl logs -n "$ns" "$pod" --all-containers --tail=200 || true

    # Crashed containers: the logs of the previous run say why
    restarts="$(kubectl get -n "$ns" "$pod" -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}' 2>/dev/null | awk '{s+=$1} END {print s+0}')"
    if [[ "$restarts" -gt 0 ]]; then
      print_sub_section "📜 Previous logs for $pod ($restarts restart(s)):"
      kubectl logs -n "$ns" "$pod" --all-containers --previous --tail=100 || true
    fi

    # Pods that never got ready: image pulls, scheduling, probes
    ready="$(kubectl get -n "$ns" "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    phase="$(kubectl get -n "$ns" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$ready" != "True" && "$phase" != "Succeeded" ]]; then
      print_sub_section "🔍 Describe $pod (not ready):"
      kubectl describe -n "$ns" "$pod" || true
    fi
  done
}

debug_namespace "$NAMESPACE"
# Dependencies only when something failed, they are noise otherwise
if [[ "$HELM_RC" -ne 0 || "$DB_RC" -ne 0 ]]; then
  for ns in "${DEBUG_NAMESPACES[@]}"; do
    debug_namespace "$ns"
  done
fi

# --------------------------------------------------
# Exit result
# --------------------------------------------------
print_section "🎯 Result"
if [ "$HELM_RC" -ne 0 ]; then
  echo "❌ Deployment failed"
  exit "$HELM_RC"
fi
if [ "$DB_RC" -ne 0 ]; then
  echo "❌ CNPG cluster not ready"
  exit 1
fi

echo "✅ Deployment succeeded"
