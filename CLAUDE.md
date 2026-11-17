# CLAUDE.md

Claude Code instructions for this repository. The canonical, tool-agnostic instructions live in `AGENTS.md`, imported below. Area-specific rules live in `.claude/rules/`: Claude Code loads a rule when it works on files matching its `paths:` frontmatter. Put new area rules there, not in this file. Permissions (what needs a prompt, what is blocked) are in `.claude/settings.json`.

## Sub-agents

This repository defines its own agents in `.claude/agents/` (copied and adapted from TrueCharts). Use them when their description fits, so long logs and repetitive work stay out of the main context:

| Agent | Use it for |
| --- | --- |
| `Explore` | Searching the repository: finding files, tracing where something is used. Read-only, runs on Haiku (replaces the built-in `Explore`) |
| `Plan` | Designing a larger change before doing it (new app, CI rework, upgrades). Read-only, runs on Opus (replaces the built-in `Plan`) |
| `haiku-triage` | Every validation run with a long log: `kubeconform.sh`, `template_helmrelease.sh` over several releases, `flux_api_check.sh`, `pre-commit run --all-files`, `actionlint`, the Renovate validator. Start it yourself, without being asked |
| `haiku-lookup` | Quick read-only questions: where a value is set, which apps use a chart, which HelmReleases are not TrueCharts |
| `haiku-bulk-edit` | One exact, mechanical change in many files (e.g. the same line in many `helm-release.yaml`) |
| `haiku-drafter` | Commit messages and PR descriptions from a diff |
| `renovate-review` | Before merging an update (every one that isn't automerged): release notes, values changes against what this repo sets, CI and bot comments → MERGE or HOLD. Read-only, runs on Sonnet |
| `upgrade-watch` | Following a chart upgrade after it's merged (Renovate PR or manual bump) and finding out why it failed: Flux, helm-controller, rollbacks, pods, volumes, database. Read-only, runs on Sonnet |
| `cluster-health` | One health report of the whole cluster: Flux, pods, alerts, certificates, volumes, CNPG backups, VolSync. After maintenance, around a rebootstrap, or when asked. Read-only |
| `leak-check` | Before every commit or push: unencrypted secrets, token-like strings, hardcoded domains/IPs, files that must never be committed. This repository is public. Read-only |
| `new-app` | Adding an app: ks.yaml, kustomization, HelmRelease from a similar app, plus dummyEnv, CI overrides and the schema exclusion. Validates, does not commit. Runs on Sonnet |
| `ci-triage` | A failed GitHub Actions run: which job and step failed, the error lines, and which required check it blocks. Read-only |

- Give the agent the exact command or change, the files, and what to return. Tell `haiku-triage` not to fix anything; fix what it reports yourself, then run it again.
- A quick check on one file with short output may run directly.
- Check an agent's result before relying on it.

## Working with the cluster

- `.claude/settings.json` allows read-only `kubectl`, `flux`, `talosctl` and `helm` commands without a prompt, asks before anything that changes the cluster, and blocks decrypting secrets. Do not try to get around a blocked command another way (another tool, `sh -c`, a script): ask the user instead.
- The `.envrc` (loaded by direnv) sets `TALOSCONFIG` and `SOPS_AGE_KEY_FILE`, and the kubeconfig is at `~/.kube/config`, so cluster tools work without extra flags.

@AGENTS.md
