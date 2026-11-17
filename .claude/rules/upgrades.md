---
paths:
  - "clusters/main/kubernetes/flux-system/**"
  - "clusters/main/kubernetes/system/system-upgrade/**"
  - "clusters/main/talos/**"
  - "repositories/oci/flux-manifests.yaml"
description: "Rules for Talos, Kubernetes and Flux upgrades"
---

# Talos, Kubernetes and Flux upgrades

These rules apply to the files that control the cluster's base versions. They add to [`AGENTS.md`](../../AGENTS.md). A mistake here can take down the whole (single-node) cluster.

## Talos and Kubernetes

- `clusters/main/kubernetes/flux-system/flux/upgradesettings.yaml` sets `TALOS_VERSION` and `KUBERNETES_VERSION`. tuppr (`system/system-upgrade/`) upgrades the node to them; its `TalosUpgrade`/`KubernetesUpgrade` objects use these as `${VARS}`.
- This file is the source of truth. `clusters/main/talos/talconfig.yaml` may show older versions and is only used to generate machine configs.
- The Kubernetes version must be supported by the Talos version. CI checks it (`talos_k8s_compat.sh`, PR comment "Talos / Kubernetes compatibility"). Check it before changing either:

  ```bash
  bash .github/scripts/talos_k8s_compat.sh
  ```

- Talos and Kubernetes updates are not automerged. Upgrade Talos before a Kubernetes minor that needs it, in a separate PR.
- Never run `talosctl upgrade`, `upgrade-k8s`, `apply-config`, `reboot`, `reset` or `clustertool` commands that change the node, unless the user explicitly asks.
- Cluster-level to-dos for the next rebootstrap are in `TODO-after-rebootstrap.md`.

## Flux

- The Flux version is the tag in `repositories/oci/flux-manifests.yaml`; Flux installs itself from that OCI artifact (`flux-system/flux/flux.yaml`).
- Use the latest API version the cluster's Flux serves. The daily "Flux API Migrate" workflow opens a PR for deprecated ones; check by hand with:

  ```bash
  bash .github/scripts/flux_api_check.sh
  ```

- A Flux upgrade PR is checked against the new version's API versions. If it fails, migrate in the same PR (`flux migrate -f clusters --yes` with the new Flux CLI).
- Changes to `flux-entry.yaml` patches (decryption, substitution, HelmRelease defaults) affect every app. Keep them minimal and explain them in the PR.
