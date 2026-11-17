#!/usr/bin/env bash
set -o errexit
set -o pipefail

KUBERNETES_DIR=$1

[[ -z "${KUBERNETES_DIR}" ]] && echo "Kubernetes location not specified" && exit 1

kustomize_args=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# Validate core resources against the Kubernetes version the cluster runs (without the "v")
KUBERNETES_VERSION="$(yq '.data.KUBERNETES_VERSION' clusters/main/kubernetes/flux-system/flux/upgradesettings.yaml)"
KUBERNETES_VERSION="${KUBERNETES_VERSION#v}"
echo "=== Kubernetes version: ${KUBERNETES_VERSION} ==="

# No -ignore-missing-schemas: a kind without a schema fails, add it to -skip on purpose instead.
# Secrets and ConfigMaps are skipped because the SOPS metadata fails strict validation.
# The tuppr upgrades use Flux substitution variables (${TALOS_VERSION}) that fail the version pattern.
kubeconform_args=(
    "-strict"
    "-kubernetes-version"
    "${KUBERNETES_VERSION}"
    "-skip"
    "Secret,ConfigMap,tuppr.home-operations.com/v1alpha1/TalosUpgrade,tuppr.home-operations.com/v1alpha1/KubernetesUpgrade"
    "-schema-location"
    "default"
    "-schema-location"
    "https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

echo "=== Validating standalone manifests in ${KUBERNETES_DIR} ==="
find "${KUBERNETES_DIR}" -maxdepth 1 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
do
    kubeconform "${kubeconform_args[@]}" "${file}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        exit 1
    fi
done

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/ ==="
find "${KUBERNETES_DIR}" -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
do
    echo "=== Validating kustomizations in ${file/%$kustomize_config} ==="
    kustomize build "${file/%$kustomize_config}" "${kustomize_args[@]}" | kubeconform "${kubeconform_args[@]}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        exit 1
    fi
done