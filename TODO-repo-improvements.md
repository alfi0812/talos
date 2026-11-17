# Repo and tooling improvements

Ideas to make the repo and the devcontainer easier to maintain. Separate from
[TODO-after-rebootstrap.md](TODO-after-rebootstrap.md), which is about the cluster itself.

## Apps

- [ ] Replace **readarr**: the TrueCharts chart is deprecated (last version 26.1.5, still on common
      28.16.6) and upstream Readarr is retired. Candidates: LazyLibrarian (TrueCharts chart
      `lazylibrarian`), or a maintained Readarr fork (no TrueCharts chart).

## GitHub Actions

- [ ] `actions/create-github-app-token`: switch `app-id` to `client-id` (the bot app's Client ID, from the
      GitHub App settings). Add it as a new secret (e.g. `BOT_CLIENT_ID`) and replace
      `app-id: ${{ secrets.BOT_APP_ID }}` in all 9 workflows that generate a bot token:
      automerge, flate, flux-migrate, kubeconform, label-sync, labeler, pr-install, repo-checks, tag.
      `app-id` still works, the action only recommends `client-id`.

## Claude Code

- [ ] `CLAUDE.md`: repo layout, clustertool/talhelper workflow, sops rules, Renovate, how Flux deploys
- [ ] `.claude/settings.json`: deny reading `age.agekey`, `**/.decrypted~*` and running `sops -d`
- [ ] `.claude/settings.json`: allow read-only cluster commands (`kubectl get/describe/logs`,
      `flux get`, `talosctl get/health`, `helm list`) without a prompt
- [ ] Optional: Flux MCP server (`flux-operator-mcp`) for Flux status and events
