#!/usr/bin/env bash
# Checks that every Flux object in the repo uses an API version that the cluster's Flux version
# serves. The served versions come from the CRDs in the flux-manifests artifact the cluster
# installs (repositories/oci/flux-manifests.yaml), so a Flux upgrade PR is checked against the
# new version.
#   - not served:  error (Flux would fail to apply it)
#   - deprecated:  warning (still works; the daily "Flux API Migrate" workflow upgrades it)
#
# Writes a Markdown report to $FLUX_API_REPORT (if set) and to the GitHub job summary, and sets
# the step outputs "unsupported" and "deprecated" (counts).
#
# Usage: flux_api_check.sh   (from the repo root; needs flux and yq)
set -euo pipefail

FLUX_VERSION="$(yq '.spec.ref.tag' repositories/oci/flux-manifests.yaml)"
FLUX_URL="$(yq '.spec.url' repositories/oci/flux-manifests.yaml)"
echo "=== Flux version of the cluster: ${FLUX_VERSION} ==="

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/manifests"
flux pull artifact "${FLUX_URL}:${FLUX_VERSION}" --output "$WORK_DIR/manifests" >/dev/null

# "group/version<TAB>kind<TAB>served<TAB>deprecated<TAB>storage" for every CRD version
find "$WORK_DIR/manifests" -name '*.yaml' -print0 | xargs -0 cat \
  | yq -N 'select(.kind == "CustomResourceDefinition")
      | .spec.group as $g | .spec.names.kind as $k
      | .spec.versions[]
      | [$g + "/" + .name, $k, (.served // false), (.deprecated // false), (.storage // false)] | @tsv' \
  > "$WORK_DIR/served.tsv"

# "file<TAB>apiVersion<TAB>kind<TAB>name" for every Flux object in the repo
find clusters repositories -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
  | xargs -0 yq -N 'select((.apiVersion // "") | test("\.fluxcd\.io/")) | [filename, .apiVersion, .kind, .metadata.name] | @tsv' \
  | grep -v '^[[:space:]]*$' > "$WORK_DIR/used.tsv" || true

# The API version to move to: the storage version of that kind
recommended() {
  local group="${1%/*}" kind="$2"
  awk -F'\t' -v g="$group/" -v k="$kind" 'index($1, g) == 1 && $2 == k && $5 == "true" { print $1 }' "$WORK_DIR/served.tsv"
}

unsupported_rows=()
deprecated_rows=()
while IFS=$'\t' read -r file api kind name; do
  match="$(awk -F'\t' -v a="$api" -v k="$kind" '$1 == a && $2 == k' "$WORK_DIR/served.tsv")"
  target="$(recommended "$api" "$kind")"
  if [[ -z "$match" ]] || [[ "$(cut -f3 <<< "$match")" != "true" ]]; then
    echo "::error file=${file}::${kind} ${name} uses ${api}, which Flux ${FLUX_VERSION} does not serve${target:+ (use ${target})}"
    suggestion="_kind not served_"
    [[ -n "$target" ]] && suggestion="\`${target}\`"
    unsupported_rows+=("| \`${file}\` | ${kind} \`${name}\` | \`${api}\` | ${suggestion} |")
  elif [[ "$(cut -f4 <<< "$match")" == "true" ]]; then
    echo "::warning file=${file}::${kind} ${name} uses ${api}, which is deprecated in Flux ${FLUX_VERSION} (use ${target})"
    deprecated_rows+=("| \`${file}\` | ${kind} \`${name}\` | \`${api}\` | \`${target}\` |")
  fi
done < "$WORK_DIR/used.tsv"

total="$(wc -l < "$WORK_DIR/used.tsv")"
echo "=== Flux objects in use ==="
cut -f2,3 "$WORK_DIR/used.tsv" | sort | uniq -c
echo "=== ${total} objects, ${#unsupported_rows[@]} not served, ${#deprecated_rows[@]} deprecated ==="

# --------------------------------------------------
# Markdown report (PR comment and job summary)
# --------------------------------------------------
{
  echo "## 🔄 Flux API versions"
  echo ""
  echo "Checked ${total} Flux objects against **Flux ${FLUX_VERSION}**, the version the cluster runs."
  echo ""
  if [[ ${#unsupported_rows[@]} -eq 0 && ${#deprecated_rows[@]} -eq 0 ]]; then
    echo "✅ All Flux objects use current API versions."
  fi
  if [[ ${#unsupported_rows[@]} -gt 0 ]]; then
    echo "### ❌ Not supported (${#unsupported_rows[@]})"
    echo ""
    echo "Flux ${FLUX_VERSION} does not serve these API versions, so Flux would fail to apply them. **This PR can't be merged until they are fixed.**"
    echo ""
    echo "| File | Object | API version | Use instead |"
    echo "|------|--------|-------------|-------------|"
    printf '%s\n' "${unsupported_rows[@]}"
    echo ""
  fi
  if [[ ${#deprecated_rows[@]} -gt 0 ]]; then
    echo "### ⚠️ Deprecated (${#deprecated_rows[@]})"
    echo ""
    echo "These still work, but will be removed in a future Flux version. The daily **Flux API Migrate** workflow opens a PR that upgrades them, or run \`flux migrate -f . --yes\` yourself."
    echo ""
    echo "| File | Object | API version | Use instead |"
    echo "|------|--------|-------------|-------------|"
    printf '%s\n' "${deprecated_rows[@]}"
    echo ""
  fi
} > "$WORK_DIR/report.md"

if [[ -n "${FLUX_API_REPORT:-}" ]]; then
  cp "$WORK_DIR/report.md" "$FLUX_API_REPORT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$WORK_DIR/report.md" >> "$GITHUB_STEP_SUMMARY"
fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "unsupported=${#unsupported_rows[@]}" >> "$GITHUB_OUTPUT"
  echo "deprecated=${#deprecated_rows[@]}" >> "$GITHUB_OUTPUT"
fi

if [[ ${#unsupported_rows[@]} -gt 0 ]]; then
  exit 1
fi
