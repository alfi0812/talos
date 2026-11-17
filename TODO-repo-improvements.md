# Repo and tooling improvements

Ideas to make the repo and the devcontainer easier to maintain. Separate from
[TODO-after-rebootstrap.md](TODO-after-rebootstrap.md), which is about the cluster itself.

## Schemas and validation

- [x] VS Code: TrueCharts HelmReleases use the versioned TrueCharts HelmRelease schema, mapped centrally
      in `.vscode/settings.json`; Renovate bumps it (`.github/renovate/special_truechartsSchema.json5`)
- [x] VS Code: generic Flux HelmRelease schema mapped to every HelmRelease in `.vscode/settings.json`

## CI rework

- [x] `helm template` job (no cluster) in `pr-install.yaml` for every changed HelmRelease, skip list
      included, before the install job (`.github/scripts/template_helmrelease.sh`). Helm validates
      the values against the chart's own `values.schema.json` (TrueCharts: exactly the common
      version the chart ships)
- [x] ~~`pr-install.yaml`: re-enable the `paths:` filter~~ Not possible: the ruleset requires its
      `Summary` check and automerge is triggered by this workflow, so PRs without HelmRelease changes
      would never be mergeable. The `detect` job already skips the expensive jobs for those PRs.
- [x] `pr-install.yaml`: pinned yq, k3d and `nolar/setup-k3d-k3s` (Renovate annotations); kubectl and
      K3s follow the cluster's Kubernetes version from `talconfig.yaml` (K3s: newest patch of the
      same minor). The CI dependencies in `deploy_helmrelease.sh` (CNPG, cert-manager, Prometheus
      Operator CRDs, MetalLB) use the versions from the cluster's HelmReleases.
- [x] `kubeconform.sh`: moved to `k8s-schemas.home-operations.com` (the old `kubernetes-schemas.pages.dev`
      lacks Longhorn and answers missing schemas with an HTML page, so they were silently skipped),
      removed `-ignore-missing-schemas`, validates against the cluster's Kubernetes version
- [x] Switched the 30 `# yaml-language-server` comments from `kubernetes-schemas.pages.dev` to
      `k8s-schemas.home-operations.com`
- [x] `kubeconform.yaml`: kubeconform, kustomize and yq pinned as release binaries (Renovate annotations;
      kustomize needs the `extractVersion` rule in `customManagers.json5`), Homebrew and the unused flux removed
- [ ] When talhelper/`talconfig.yaml` goes away with the next clustertool update: `pr-install.yaml` and
      `kubeconform.sh` read the cluster's Kubernetes version from `clusters/main/talos/talconfig.yaml`,
      point them to the new location

## Flux API versions

- [ ] Migrate the Provider/Alert manifests from `notification.toolkit.fluxcd.io/v1beta3` to `v1`
      (`flux migrate -f . --yes`; Flux CLI 2.10 reports exactly these, everything else is current):
  - `clusters/main/components/notifications/discord/notification.yaml` (1 Provider, 2 Alerts)
  - `clusters/main/kubernetes/flux-system/notifications/github/provider.yaml` (1 Provider, 1 Alert)
- [ ] Automate: Renovate only bumps versions, it can't rewrite `apiVersion`s by itself. Options:
  - Renovate `postUpgradeTasks` on Flux updates, running `flux migrate -f . --yes` (needs the `flux`
    binary in the self-hosted Renovate image and the command in `allowedPostUpgradeCommands`)
  - A GitHub workflow on PRs that runs `flux migrate -f . --dry-run` and fails when it would change
    anything (simplest), or runs it with `--yes` and pushes the fix commit

## Apps

- [ ] Replace **readarr**: the TrueCharts chart is deprecated (last version 26.1.5, still on common
      28.16.6) and upstream Readarr is retired. Candidates: LazyLibrarian (TrueCharts chart
      `lazylibrarian`), or a maintained Readarr fork (no TrueCharts chart).

## Devcontainer

- [x] Persist Claude Code login, `gh` login and `~/.kube` across rebuilds
- [ ] Persist fish history (`/config/.local/share/fish`) and krew plugins (`/config/.krew`) in named volumes
- [ ] Remove `postCreateCommand` (`npm install`, there is no `package.json`) and probably the node feature
- [ ] Extensions: remove `weaveworks.vscode-gitops-tools` (unmaintained since Weaveworks shut down)
- [ ] Extensions: keep at most one of the four Helm extensions (they mostly help chart authors)
- [ ] Extensions: add `github.vscode-github-actions`
- [ ] Keep the extension list in one place (`devcontainer.json` or `.vscode/extensions.json`)

## Claude Code

- [ ] `CLAUDE.md`: repo layout, clustertool/talhelper workflow, sops rules, Renovate, how Flux deploys
- [ ] `.claude/settings.json`: deny reading `age.agekey`, `**/.decrypted~*` and running `sops -d`
- [ ] `.claude/settings.json`: allow read-only cluster commands (`kubectl get/describe/logs`,
      `flux get`, `talosctl get/health`, `helm list`) without a prompt
- [ ] Optional: Flux MCP server (`flux-operator-mcp`) for Flux status and events
