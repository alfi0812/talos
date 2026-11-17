# CLAUDE.md

Claude Code instructions for this repository. The canonical, tool-agnostic instructions live in `AGENTS.md`, imported below. Area-specific rules live in `.claude/rules/`: Claude Code loads a rule when it works on files matching its `paths:` frontmatter. Put new area rules there, not in this file. Permissions (what needs a prompt, what is blocked) are in `.claude/settings.json`.

## Sub-agents

This repository defines small Haiku agents in `.claude/agents/`. Use them when their description fits, so long logs and repetitive work stay out of the main context:

| Agent | Use it for |
| --- | --- |
| `haiku-triage` | Every validation run with a long log: `kubeconform.sh`, `template_helmrelease.sh` over several releases, `flux_api_check.sh`, `pre-commit run --all-files`, `actionlint`, the Renovate validator. Start it yourself, without being asked |
| `haiku-lookup` | Quick read-only questions: where a value is set, which apps use a chart, which HelmReleases are not TrueCharts |
| `haiku-bulk-edit` | One exact, mechanical change in many files (e.g. the same line in many `helm-release.yaml`) |
| `haiku-drafter` | Commit messages and PR descriptions from a diff |

- Give the agent the exact command or change, the files, and what to return. Tell `haiku-triage` not to fix anything; fix what it reports yourself, then run it again.
- A quick check on one file with short output may run directly.
- Check an agent's result before relying on it.

## Working with the cluster

- `.claude/settings.json` allows read-only `kubectl`, `flux`, `talosctl` and `helm` commands without a prompt, asks before anything that changes the cluster, and blocks decrypting secrets. Do not try to get around a blocked command another way (another tool, `sh -c`, a script): ask the user instead.
- The `.envrc` (loaded by direnv) sets `TALOSCONFIG` and `SOPS_AGE_KEY_FILE`, and the kubeconfig is at `~/.kube/config`, so cluster tools work without extra flags.

@AGENTS.md
