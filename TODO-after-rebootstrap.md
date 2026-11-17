# To-do after the rebootstrap (Samsung 990 Pro)

Checklist for after the cluster is bootstrapped again on the new drive.
Domains are written as `${DOMAIN_0}` / `${DOMAIN_1}` like in the manifests.

## 0. Right before the rebootstrap (old drive)

- [ ] Copy the newest Tdarr backup to the NFS share (in-cluster copy, `kubectl cp` breaks off on large files):
      ```sh
      kubectl -n media exec deploy/tdarr -c tdarr -- sh -c \
        'F=$(ls -t /app/server/Tdarr/Backups/*.zip | head -1); mkdir -p /media/.tdarr-backup; cp "$F" /media/.tdarr-backup/; sha256sum "$F" /media/.tdarr-backup/$(basename "$F")'
      ```
      Both checksums must match.
- [ ] Take fresh backups: trigger a manual volsync sync for the important apps and a CNPG backup
      per cluster. Afterwards remove `spec.trigger.manual` again so the daily schedule keeps running.
- [ ] In the commit the new cluster is bootstrapped from: set `dest.enabled: true` for the
      Stirling-PDF `configs` volsync entry (`general/stirling-pdf/app/helm-release.yaml`).
      It is `false` on the old cluster because a restore source can only be set when the PVC is created.

## 1. Verify the fresh install

- [ ] `talosctl get securitystate`: Secure Boot is active
- [ ] `talosctl get volumestatus STATE EPHEMERAL -o yaml`: both show `encryptionProvider: luks2` with a TPM key
- [ ] The second key slot (recovery) for the encrypted volumes is stored in the password manager
- [ ] Node, Cilium and Flux are healthy; all Kustomizations and HelmReleases are `Ready`
- [ ] Image GC uses the new values (50/30, `imageMinimumGCAge` 30m) and `maxPods` is 500
- [ ] etcd runs with its default heartbeat/election timeouts. Watch the logs for
      `apply request took too long` or leader elections; if they show up, restore
      `heartbeat-interval: "250"` / `election-timeout: "2500"` in `patches/etcd.yaml`
- [ ] Old Samsung P3 removed and securely erased (`nvme format` / Secure Erase)

## 2. Check that the restores worked

- [ ] CNPG clusters came up from MinIO (`mode: recovery`): authelia, lldap, vaultwarden,
      nextcloud, kitchenowl, seerr, radarr, sonarr, sonarr-anime
- [ ] Spot-check data: Radarr movies, Sonarr series, LLDAP users and groups (`admin`, `users`, adrian)
- [ ] Volsync restored the config PVCs (`dest` enabled), especially wg-easy (OIDC link of `admin`)
      and Stirling-PDF (user database: SSO admins keep their Admin role)
- [ ] All volsync `ReplicationSource`s have a `nextSyncTime` and none has `trigger.manual` set
- [ ] First nightly CNPG backup after the restore succeeded for every cluster

### Apps without a full backup

- [ ] **tdarr**: restore libraries, flows and settings from the zip in `/media/.tdarr-backup/`
      (Tdarr UI → Tools → Backups → upload/restore). Scan data is rebuilt by Tdarr itself.
- [ ] **hastebin**: starts without pastes
- [ ] **gatus / grafana**: databases start fresh (dashboards from config come back on their own)

## 3. Move the Talos config to the 1.14 format

The repo still generates Talos 1.13-style configs, and talhelper refuses Kubernetes 1.37
with them. Move the patches to the 1.14 multi-document format:

- [ ] `patches/controlplane.yaml`: `cluster.apiServer` → `KubeAPIServerConfig`,
      `admissionControl` → `KubeAdmissionControlConfig`, `controllerManager` →
      `KubeControllerManagerConfig`, `scheduler` → `KubeSchedulerConfig`, `proxy` → `KubeProxyConfig`
- [ ] `patches/all.yaml`: `machine.features.hostDNS` → `hostDNS` in `ResolverConfig`; drop `cluster.proxy`
- [ ] Set `talosVersion` / `kubernetesVersion` in `talconfig.yaml` to what the node runs
- [ ] `talhelper genconfig` succeeds, then `talosctl apply-config --dry-run` shows only expected changes
- [ ] Do **not** enable workload isolation (`SecurityProfileConfig`) until Longhorn's iSCSI is tested with it
- [ ] Renovate: allow Talos minor bumps in `talconfig.yaml` again
- [ ] Optional: report the talhelper `KubeEtcdEncryptionConfig` key name bug (`key1` instead of `key2`) upstream

## 4. OIDC for kube-apiserver, kubectl and Headlamp

- [ ] Talos static host entry: `auth.${DOMAIN_1}` → internal ingress IP, so kube-apiserver
      fetches Authelia's keys without going through the internet
- [ ] `KubeAuthenticationConfig`: issuer `https://auth.${DOMAIN_1}`, audiences
      `kubernetes` and `headlamp` (`MatchAny`), username from `preferred_username`,
      groups from `groups`, both prefixed with `oidc:`
- [ ] RBAC: `ClusterRoleBinding` group `oidc:admin` → `cluster-admin`
- [ ] Authelia clients in `auth/authelia/app/oidc-clients.yaml`:
  - [ ] `kubernetes`: public, PKCE, redirect `http://localhost:8000` (kubelogin)
  - [ ] `headlamp`: confidential, redirect `https://kube.${DOMAIN_1}/oidc-callback`
  - [ ] `claims_policy` that puts `groups` and `preferred_username` into the **ID token**
- [ ] Headlamp: OIDC settings, remove forward-auth from its ingress
- [ ] kubectl: kubelogin context for OIDC; keep the certificate kubeconfig as break-glass access
- [ ] Before pushing: validate the Authelia config with the real binary
      (`authelia validate-config`) and check each client hash (`authelia crypto hash validate`)

## 5. Kubernetes 1.37

- [ ] Cilium and Flux officially support 1.37 (Cilium 1.21 / Flux 2.10); upgrade them if not done yet

## 6. Optional: Flux MCP server for Claude

- [ ] Decide whether to add the Flux MCP server (`flux-operator-mcp`, by ControlPlane). It gives AI tools
      structured access to Flux (resource status, reconcile errors, events, tracing, Flux docs search).
      The `flux` CLI already covers this, so it is a nice-to-have
- [ ] If yes: install it in the devcontainer, start it **read-only** (`--read-only`), register it in
      `.mcp.json`, and add `mcp__flux-operator-mcp__*` permission rules to `.claude/settings.json`
      (MCP tools are not covered by the Bash rules). Some of its reports assume Flux Operator
      (`FluxInstance`); this cluster installs Flux from the `flux-manifests` artifact

## 7. After the clustertool update (talhelper removed)

Check that the AI rules and CI still match the new clustertool once it no longer uses talhelper:

- [ ] Talos config layout: does `clusters/main/talos/` still have `talconfig.yaml`, `patches/` and
      `generated/` (machine config, `talosconfig`, `talsecret.yaml`)? Update where these paths are named:
  - `AGENTS.md` (repository table, golden rules 2, 5 and 7)
  - `.claude/rules/secrets.md` and `.claude/rules/upgrades.md` (incl. their `paths:` frontmatter)
  - `.claude/agents/haiku-lookup.md` and `haiku-bulk-edit.md` (generated files they must not touch)
  - `.claude/settings.json`: the `Read(./clusters/main/talos/generated/**)` deny rule must still cover
    the plaintext machine config and `talosconfig`, wherever they move to
  - `.pre-commit-config.yaml`: the `exclude` pattern for generated and encrypted Talos files
- [ ] clustertool commands: compare `clustertool --help` with the `clustertool ...` rules in
      `.claude/settings.json` (`decrypt` denied; `encrypt`, `genconfig`, `init`, `talos`, `flux` ask;
      `checkcrypt` allowed). New commands that change files or the node need an ask rule
- [ ] Git hook: clustertool may rewrite `.git/hooks/pre-commit`. Make sure it still runs the encryption
      check (`clustertool precommit`) and re-add the `pre-commit run` part if it's gone
- [ ] `.sops.yaml`: if clustertool changes the encryption rules, update `.claude/rules/secrets.md`
- [ ] CI: run the checks once on a PR (`Repo Checks`, `Kubeconform`, `Pull Request: Install`) and look at
      the bot comments. The versions CI uses come from `upgradesettings.yaml` and the HelmReleases, not
      from `talconfig.yaml`, so they should be unaffected
