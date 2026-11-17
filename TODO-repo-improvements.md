# Repo and tooling improvements

Ideas to make the repo and the devcontainer easier to maintain. Separate from
[TODO-after-rebootstrap.md](TODO-after-rebootstrap.md), which is about the cluster itself.

## Apps

- [ ] Replace **readarr**: the TrueCharts chart is deprecated (last version 26.1.5, still on common
      28.16.6) and upstream Readarr is retired. Candidates: LazyLibrarian (TrueCharts chart
      `lazylibrarian`), or a maintained Readarr fork (no TrueCharts chart).

## Claude Code

- [ ] Optional, skipped for now: enable the Claude Code sandbox (`sandbox` in `.claude/settings.json`) so
      the secret files are blocked at OS level too. The permission rules only match the commands Claude
      writes, not a script or `sh -c` that reads a file itself. Needs a devcontainer change first:
      bubblewrap can't create namespaces under Docker's default seccomp profile, so the container needs
      `"runArgs": ["--security-opt", "seccomp=unconfined"]` (or a custom profile that only allows
      namespaces) plus `bubblewrap`, `socat` and `@anthropic-ai/sandbox-runtime`. The sandbox must then
      also block the Docker socket, and run `kubectl`, `talosctl`, `flux`, `helm`, `gh`, `docker` and
      `git push` outside it (`excludedCommands`)
- [ ] Keep `AGENTS.md` and `.claude/rules/` up to date when the layout or CI changes (the clustertool
      update has its own checklist in `TODO-after-rebootstrap.md`, section 7)
