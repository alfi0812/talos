# AGENTS.md

Instructions for AI coding agents working in this repository (Claude Code, GitHub Copilot, Codex and any other tool that reads `AGENTS.md`).

- **`AGENTS.md`** (this file) is the canonical, tool-agnostic source.
- **`CLAUDE.md`** imports this file and adds the Claude Code specifics (sub-agents).
- **`.claude/rules/*.md`** hold area-specific rules. Claude Code loads each one when it works on files matching its `paths:` frontmatter. Other agents **must read the matching file before editing**:

| When you change files in | Read first |
| --- | --- |
| `clusters/**/helm-release.yaml`, `ci/**`, `.vscode/settings.json` | [`.claude/rules/helm-releases.md`](.claude/rules/helm-releases.md) |
| `*.secret.yaml`, `clusterenv.yaml`, `.sops.yaml`, `clusters/main/talos/**` | [`.claude/rules/secrets.md`](.claude/rules/secrets.md) |
| `.github/**`, `.pre-commit-config.yaml` | [`.claude/rules/github.md`](.claude/rules/github.md) |
| `upgradesettings.yaml`, `clusters/main/talos/**`, `system-upgrade/**`, `flux-system/**` | [`.claude/rules/upgrades.md`](.claude/rules/upgrades.md) |

## Repository overview

GitOps configuration of a personal single-node **Talos Linux** Kubernetes cluster, reconciled by **FluxCD**. Apps are mostly [TrueCharts](https://truecharts.org) Helm charts. Secrets are encrypted with **SOPS** (age). The Talos config is generated with **clustertool** (TrueCharts' wrapper around talhelper).

| Path | Contents |
| --- | --- |
| `clusters/main/kubernetes/` | Everything Flux deploys, entry point `flux-entry.yaml`. One folder per namespace group (`apps`, `auth`, `core`, `media`, `networking`, `observability`, `system`, ...) |
| `clusters/main/kubernetes/<group>/<app>/ks.yaml` | Flux `Kustomization` of one app, pointing at its `app/` folder |
| `clusters/main/kubernetes/<group>/<app>/app/` | The app: `helm-release.yaml`, `kustomization.yaml`, optional `*.secret.yaml`, PVCs, ... |
| `clusters/main/kubernetes/flux-system/flux/` | Flux itself (`flux.yaml`, installed from the `flux-manifests` OCI artifact) and `upgradesettings.yaml` (Talos and Kubernetes versions for tuppr) |
| `clusters/main/components/` | Kustomize components shared by several apps (e.g. Discord notifications) |
| `clusters/main/clusterenv.yaml` | SOPS-encrypted cluster variables (`${DOMAIN_0}`, IPs, ...), substituted by Flux into every Kustomization |
| `clusters/main/talos/` | Talos config: `talconfig.yaml`, `patches/`, `generated/` (machine config and `talosconfig`, generated and gitignored, except the encrypted `talsecret.yaml`) |
| `repositories/` | Flux sources: `helm/` (HelmRepositories), `oci/` (OCIRepositories), `git/` |
| `ci/` | CI test overrides per chart (`ci/<chart>.yaml`) and `ci/.config.yaml` (install-test skip list and dummy env vars) |
| `.github/workflows/`, `.github/scripts/` | CI (see [CI checks](#ci-checks)) and its helper scripts |
| `.github/renovate.json5`, `.github/renovate/` | Renovate config (self-hosted Mend Renovate in the cluster, bot `viserion-renovate`) |
| `TODO-*.md` | Open work: cluster to-dos and repository improvements |

## How a change reaches the cluster

1. A change is merged into `main` (directly or through a PR that passed the required checks).
2. Flux's `flux-entry` Kustomization (`clusters/main/kubernetes`) and `flux-entry-repos` (`repositories/`) pick it up. They patch every child Kustomization to:
   - decrypt SOPS files with the `sops-age` secret,
   - substitute `${VARS}` from the ConfigMaps `cluster-config` (from `clusterenv.yaml`) and `upgrade-settings`,
   - apply HelmRelease defaults (CRDs `CreateReplace`, 3 remediation retries, `RemediateOnFailure`).
   Labels opt out: `substitution.flux.home.arpa/disabled: "true"` and `helmrelease-defaults.flux.home.arpa/disabled: "true"`.
3. Each app's `ks.yaml` applies its `app/` folder; helm-controller installs the HelmRelease.

There is no other deployment path: **the cluster is changed through Git, not with `kubectl apply`.**

## Golden rules

1. **Keep changes minimal.** Stay within the requested app or area. Do not reformat or "clean up" unrelated files.
2. **Never decrypt, print or commit secrets.** Do not run `sops -d`, `sops edit`, `clustertool decrypt`, or read `age.agekey`, `.decrypted~*` files, the generated Talos machine config or `talosconfig`. New secrets go into `*.secret.yaml` files that match `.sops.yaml`, encrypted before commit. See [secrets rules](.claude/rules/secrets.md).
3. **The cluster is read-only for agents.** Inspect it freely (`kubectl get/describe/logs`, `flux get`, `talosctl get/health`), but anything that changes it (`kubectl apply/delete/patch`, `flux reconcile/suspend`, `helm upgrade`, `talosctl apply-config/upgrade/reboot`) needs the user's explicit OK, and the fix belongs in Git anyway.
4. **Leave version bumps to Renovate.** Chart, image, tool and action versions are updated by Renovate PRs. Do not bump them by hand unless asked.
5. **Do not edit generated files**: `clusters/main/talos/generated/*`, anything `clustertool genconfig` writes.
6. **Do not change CI, Renovate or repository-wide tooling** unless the task is about them.
7. **Single sources of truth for versions:**
   - Kubernetes and Talos: `clusters/main/kubernetes/flux-system/flux/upgradesettings.yaml` (what tuppr upgrades to; `talconfig.yaml` may lag behind)
   - Flux: the tag in `repositories/oci/flux-manifests.yaml`
   - Apps: `spec.chart.spec.version` in each `helm-release.yaml`
8. **Run the validation** below before finishing. If you cannot run something, say so.

## Adding or changing an app

- New app: `clusters/main/kubernetes/<group>/<app>/ks.yaml` plus `app/kustomization.yaml` and `app/helm-release.yaml`, and add `<app>/ks.yaml` to the group's `kustomization.yaml`. Copy an existing app of the same chart source as the template.
- TrueCharts charts use `sourceRef: {kind: HelmRepository, name: truecharts, namespace: flux-system}`. Other sources live in `repositories/`.
- Details (schemas, CI overrides, skip list, dummy env vars): [helm-releases rules](.claude/rules/helm-releases.md).

## Validation

Run what fits the change (from the repository root):

```bash
pre-commit run --files <changed files>                                  # whitespace, final newline, YAML syntax
clustertool checkcrypt                                                  # every file matching .sops.yaml is encrypted
bash .github/scripts/kubeconform.sh ./clusters/main/kubernetes          # schemas, against the cluster's Kubernetes version
bash .github/scripts/template_helmrelease.sh <path/to/helm-release.yaml> # renders the chart, validates values against its schema
bash .github/scripts/flux_api_check.sh                                  # Flux API versions served by the cluster's Flux
bash .github/scripts/talos_k8s_compat.sh                                # Talos supports the Kubernetes version in upgradesettings.yaml
actionlint                                                              # after workflow changes (config: .github/actionlint.yaml)
```

`template_helmrelease.sh` needs the dummy env vars from `ci/.config.yaml` for `${VARS}`: `eval "$(yq e '.dummyEnv | to_entries | .[] | "export \(.key)=\"\(.value)\""' ci/.config.yaml)"`.

## CI checks

Required on every PR (ruleset "Branch Protection"): `Summary`, `Kubeconform - Success`, `Flate - Success`, `Konflate`, `Repo Checks - Success`.

| Workflow | What it checks |
| --- | --- |
| `pr-install.yaml` ("Pull Request: Install") | Changed HelmReleases: `helm template` (values schema), then a real install in k3d with the cluster's Kubernetes version. Posts the "HelmRelease CI Report" comment |
| `kubeconform.yaml` | kubeconform over all kustomizations; Flux API versions against the cluster's Flux (PR comment "Flux API versions") |
| `repo-checks.yaml` | pre-commit, actionlint, Renovate config (`--strict`, cluster's Renovate version), Talos/Kubernetes compatibility (PR comment) |
| `flate.yaml`, Konflate app | Rendered diffs of the change |
| `flux-migrate.yaml` | Daily: opens a bot PR that migrates deprecated Flux API versions |
| `automerge.yaml` | Merges PRs labelled `automerge` once the checks pass |

## Commits and pull requests

- Conventional commits, like Renovate: `type(scope): summary`. Types: `feat` (new app or feature), `fix` (bug fix, patch update), `chore` (maintenance, no behaviour change), `ci`, `docs`. Scope: the app name (`fix(nextcloud): ...`), or `flux`, `ci`, `github-action`, `renovate`, `devcontainer`, `talos`.
- Work on a branch and open a PR, so the required checks run. Do not push to `main` or merge unless the user asks.
- PR descriptions say what changed and why, and list the validation that ran.

## Style

- YAML: 2-space indentation, final newline, no trailing whitespace (pre-commit enforces it).
- Schema comments use `# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/<group>/<kind>_<version>.json`. HelmReleases get their schemas centrally from `.vscode/settings.json`, so do not add a schema comment to a `helm-release.yaml`.
- Markdown: `-` for lists.
