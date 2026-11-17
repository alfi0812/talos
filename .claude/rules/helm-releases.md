---
paths:
  - "clusters/**/helm-release.yaml"
  - "ci/**"
  - ".vscode/settings.json"
description: "Rules for HelmReleases, their CI test overrides and their editor schemas"
---

# HelmReleases

These rules apply to `helm-release.yaml` files, `ci/` and the schema mapping in `.vscode/settings.json`. They add to [`AGENTS.md`](../../AGENTS.md).

## Chart sources

- Most apps use TrueCharts: `sourceRef: {kind: HelmRepository, name: truecharts, namespace: flux-system}` (`oci://oci.trueforge.org/truecharts`). Their values follow the TrueCharts `common` library (docs: <https://truecharts.org/common/>).
- Other charts use a HelmRepository from `repositories/helm/` or, like tuppr, `spec.chartRef` to an OCIRepository in `repositories/oci/`.
- Chart versions are bumped by Renovate. Major updates are never automerged: read the chart's changelog for breaking changes before approving one.

## Values

- Never hardcode domains, IPs or other cluster values. Use the Flux variables from `clusters/main/clusterenv.yaml`, e.g. `${DOMAIN_0}`, `${DOMAIN_1}`. The list of names is visible in that file even though the values are encrypted.
- Secrets never go into `helm-release.yaml`. Put them in an `app/<name>.secret.yaml` Secret (encrypted, see [secrets rules](secrets.md)) and reference it, e.g. `secretKeyRef` with `expandObjectName: false` for TrueCharts.
- Keep existing comments in values. Do not reorder keys you do not change.

## Editor schemas (`.vscode/settings.json`)

- Every `clusters/**/helm-release.yaml` gets the generic Flux HelmRelease schema, and TrueCharts ones additionally the versioned TrueCharts HelmRelease schema (`https://truecharts.org/schemas/helm-release/<common version>.schema.json`, kept current by Renovate).
- **When you add a HelmRelease that does not use TrueCharts, add its path to the `!` exclusion list of the TrueCharts mapping**, otherwise the editor validates it against the wrong schema.
- Do not add `# yaml-language-server` comments to `helm-release.yaml` files: a comment overrides the central mapping.

## CI

- `pr-install.yaml` templates every changed HelmRelease (values must match the chart's `values.schema.json`), then installs it in k3d.
- `ci/<chart>.yaml` holds CI-only overrides for that chart (e.g. resource limits a CI runner can't satisfy). It is merged on top of the HelmRelease values only in the install test.
- `ci/.config.yaml`:
  - `skipList`: app folders (`clusters/main/kubernetes/<group>/<app>/app`) skipped by the install test, for apps that can't run in CI. They are still templated.
  - `dummyEnv`: values for `${VARS}` in CI. **When values use a new variable, add a dummy value here**, or the template and install tests see the literal `${VAR}`.
- CI removes NFS volumes, `existingClaim` volumes, VolSync and CNPG backups/restores before installing, and creates dummy Secrets for `secretKeyRef`s with `expandObjectName: false`.

## Validate

```bash
eval "$(yq e '.dummyEnv | to_entries | .[] | "export \(.key)=\"\(.value)\""' ci/.config.yaml)"
bash .github/scripts/template_helmrelease.sh <path/to/helm-release.yaml>
bash .github/scripts/kubeconform.sh ./clusters/main/kubernetes
```
