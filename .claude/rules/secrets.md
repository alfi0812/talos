---
paths:
  - "**/*.secret.yaml"
  - "clusters/main/clusterenv.yaml"
  - ".sops.yaml"
  - "clusters/main/talos/**"
description: "Rules for SOPS-encrypted files and the Talos secrets"
---

# Secrets

These rules apply to encrypted files and the Talos config. They add to [`AGENTS.md`](../../AGENTS.md). This is a public repository: a leaked secret is public the moment it is pushed.

## Never

- Never decrypt: no `sops -d`/`--decrypt`/`decrypt`, `sops edit`, `sops exec-*`, `clustertool decrypt`.
- Never read `age.agekey`, `.decrypted~*` files, `clusters/main/talos/generated/talosconfig` or the generated machine config (`clusters/main/talos/generated/<node>.yaml`). They are gitignored and hold plaintext keys.
- Never print secret values: no `kubectl get secret -o yaml/json/jsonpath`, `helm get values/manifest/all` (rendered values contain substituted secrets), `talosctl get machineconfig`, `kubectl config view --raw`, `gh auth token`.
- Never write a real secret into an unencrypted file, a commit message, a PR, a log or a test value. Use obvious placeholders.

## How encryption works here

- `.sops.yaml` decides what is encrypted, by path:
  - `*.secret.yaml` under `clusters/.../kubernetes/` and `values.yaml` files there: keys matching `encrypted_regex` (`pass`, `secret`, `key`, `token`, `data`, `stringData`, `id`, `email`, ...)
  - `clusterenv.yaml` and `talsecret.yaml`: fully encrypted
- An encrypted file has a `sops:` block at the end. Editing an encrypted value by hand corrupts the file (the MAC no longer matches).
- To add a secret: create `app/<name>.secret.yaml` with placeholder values, add it to `app/kustomization.yaml`, and **ask the user to fill in the real values and encrypt it** (`clustertool encrypt` or `sops -e -i <file>`). Do not commit it unencrypted.
- Flux decrypts in the cluster with the `sops-age` Secret. Values in `clusterenv.yaml` become `${VARS}` for all Kustomizations.

## Check

```bash
clustertool checkcrypt   # every file matching .sops.yaml is encrypted (also runs in the git pre-commit hook)
```

`checkcrypt` only reads. Never run `clustertool encrypt`, `decrypt` or `genconfig` without the user asking: they rewrite files.
