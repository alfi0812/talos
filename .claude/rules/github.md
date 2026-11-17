---
paths:
  - ".github/**"
  - ".pre-commit-config.yaml"
description: "Rules for GitHub workflows, CI scripts, Renovate and pre-commit config"
---

# GitHub workflows, scripts and Renovate

These rules apply to `.github/` and `.pre-commit-config.yaml`. They add to [`AGENTS.md`](../../AGENTS.md).

## Workflows

- Pin every action by full commit SHA with a version comment: `uses: actions/checkout@<sha> # v7.0.1`. Renovate updates them (`helpers:pinGitHubActionDigests`).
- Pin downloaded tools with a Renovate annotation directly above the version, so the custom regex manager in `.github/renovate/customManagers.json5` updates them:

  ```yaml
  env:
    # renovate: datasource=github-releases depName=mikefarah/yq
    YQ_VERSION: v4.54.3
  ```

- Prefer versions that follow the cluster over pinned ones: the Kubernetes version from `upgradesettings.yaml`, the Flux version from `repositories/oci/flux-manifests.yaml`, the Renovate version from the mend-renovate HelmRelease, dependency versions from their HelmReleases.
- Anything that writes to GitHub (comments, PRs, labels, merges) uses the bot token:

  ```yaml
  - uses: actions/create-github-app-token@<sha> # v3.3.0
    id: app-token
    with:
      client-id: ${{ secrets.BOT_CLIENT_ID }}
      private-key: ${{ secrets.BOT_APP_PRIVATE_KEY }}
  ```

  PR comments use `mshick/add-pr-comment` with a fixed `message-id`, so each run updates one comment.
- Keep `permissions:` minimal (`contents: read` by default). Never print secrets. Pass `${{ }}` values into `run:` through `env:`, not inline.
- New check jobs go into an existing workflow with a `... - Success` job, so the required checks in the ruleset cover them. A new workflow needs its success check added to the ruleset after it is on `main`.
- Path filters belong inside the workflow (a filter job), not in `on.pull_request.paths`: a required check from a workflow that didn't start blocks the PR.
- Self-hosted runner label: `actions-runners` (declared in `.github/actionlint.yaml`).

## Scripts (`.github/scripts/`)

- Bash with `set -euo pipefail`, runnable locally from the repository root, with a header comment that says what it checks and what it needs.
- Reports for PR comments are written to a path from an env var (e.g. `FLUX_API_REPORT`) and appended to `$GITHUB_STEP_SUMMARY` when set.

## Renovate

- Config: `.github/renovate.json5` plus the presets in `.github/renovate/`, extended as `github>alfi0812/talos//.github/renovate/<file>.json5`. A new preset only takes effect once it is on `main`.
- The cluster runs Mend Renovate CE (see the mend-renovate HelmRelease). Validate with that version, `--strict` fails on options that need a migration:

  ```bash
  v=$(bash .github/scripts/renovate_version.sh)
  docker run --rm -v "$PWD/.github:/cfg:ro" -w /cfg ghcr.io/renovatebot/renovate:$v renovate-config-validator --strict --no-global renovate.json5 renovate/*.json5
  ```

  In the devcontainer (Docker outside of Docker) the `-v` mount doesn't work: pipe the files in with `tar` instead.

## Validate

```bash
actionlint
pre-commit run --files <changed files>
```
