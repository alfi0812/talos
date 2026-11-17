# Repo and tooling improvements

Ideas to make the repo and the devcontainer easier to maintain. Separate from
[TODO-after-rebootstrap.md](TODO-after-rebootstrap.md), which is about the cluster itself.

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
