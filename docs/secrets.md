# Secrets Management

This document describes how secrets (API keys, tokens, passwords) are managed
across the macOS host and NixOS VM in this configuration.

## Architecture overview

A hybrid approach: **sops-nix** handles offline boot-time secrets,
**rbw (Bitwarden)** handles live runtime secrets for applications.

```
┌─────────────────────────────────────────────────────────────────┐
│ macOS Host                                                      │
│                                                                 │
│  Bitwarden Vault (source of truth for all secrets)              │
│       │                                                         │
│       ▼                                                         │
│  rbw (unlocked) ──► make secrets/collect                        │
│                        │                                        │
│                        ▼                                        │
│                 machines/secrets.yaml (age-encrypted)            │
│                        │                                        │
│                        ▼                                        │
│                 make vm/copy ──► rsync to VM                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ NixOS VM                                                        │
│                                                                 │
│  Boot ──► sops-nix decrypts secrets.yaml                        │
│              │                                                  │
│              ├──► /run/secrets/tailscale/auth-key                │
│              │       └──► services.tailscale.authKeyFile         │
│              │                                                  │
│              ├──► /run/secrets/rbw/email (owner=m)               │
│              │       └──► systemd: rbw-config writes config.json │
│              │                                                  │
│              ├──► /run/secrets/rbw/master-password (owner=m)     │
│              │                                                   │
│              └──► /run/secrets/uniclip/password (owner=m)         │
│                      └──► uniclip systemd user service            │
│                                                                  │
│  Login ──► systemd: rbw-config → rbw-unlock                     │
│              │  rbw-config writes ~/.config/rbw/config.json      │
│              │  rbw-unlock reads master-password, unlocks vault  │
│              ▼                                                  │
│           rbw unlocked ──► apps fetch secrets on demand          │
│              │                                                  │
│              ├──► gh()        → rbw get github-token             │
│              ├──► codex       → rbw get openai-api-key           │
│              ├──► sentry-cli  → rbw get sentry-auth-token        │
│              ├──► claude      → rbw get claude-oauth-token        │
│              ├──► with-openai → rbw get openai-api-key           │
│              └──► with-amp    → rbw get amp-api-key              │
└─────────────────────────────────────────────────────────────────┘
```

## What goes through sops vs what goes through rbw

| Secret | Delivery | Why |
|--------|----------|-----|
| `rbw/email` | sops → file → rbw-config systemd | Keeps Bitwarden account email out of public repo. Written to rbw config.json at login. |
| `rbw/master-password` | sops → file → systemd | Chicken-and-egg: needed to unlock rbw itself. Must be available at boot without network interaction. |
| `tailscale/auth-key` | sops → file → tailscale service | System service that starts before user login. Cannot depend on rbw. |
| `uniclip/password` | sops → file → uniclip user service | Avoids rbw unlock dependency for clipboard sync during bootstrap/login. |
| `github-token` | rbw → shell function | User-interactive. Fetched fresh each invocation. |
| `claude-oauth-token` | rbw → apiKeyHelper | Claude Code's native mechanism. Auto-refreshes every 5 min. |
| `openai-api-key` | rbw → wrapper script | Only injected into codex process env. |
| `sentry-auth-token` | rbw → wrapper script | Only injected into sentry-cli process env. |
| `amp-api-key` | rbw → shell alias | Ad-hoc: `with-amp some-command`. |

**Rule of thumb**: if the secret is needed before user login or without network, it
goes through sops. Everything else goes through rbw live.

## Decision log

### Why sops-nix + sopsidy (not agenix, not git-crypt)

- **agenix**: one file per secret, binary git diffs, no templating. sops-nix
  puts multiple secrets in one YAML with readable key diffs.
- **git-crypt**: secrets land in the Nix store (world-readable). Unacceptable
  for multi-user or remote systems.
- **sopsidy**: extends sops-nix with `collect.rbw.id` option so secrets are
  pulled from Bitwarden automatically. No manual `sops edit`. Running
  `collect-secrets` reads from rbw and encrypts in one step.

### Why rbw (not 1Password CLI, not plain sops)

- **1Password CLI (`op`)**: requires a running 1Password desktop app or
  service account for `op://` references. Works on macOS where the GUI runs.
  Does not work headless on a NixOS VM without extra infrastructure.
- **rbw**: background agent (`rbw-agent`) holds keys in memory like
  `ssh-agent`. Fast repeated lookups. Works headless via pinentry-tty.
  The `programs.rbw` home-manager module declaratively manages config.
- **Plain sops for everything**: every secret rotation requires re-running
  `collect-secrets` and redeploying. rbw fetches the latest value on each
  invocation — no redeploy needed for rotated tokens.

### Why wrapper scripts (not global env vars)

Environment variables set in `home.sessionVariables` or shell init are:
- Visible in `/proc/PID/environ` to any process running as the same user.
- Inherited by all child processes, crossing security boundaries.
- Persisted in shell history if set interactively.

Wrapper scripts (`writeShellScriptBin`) and shell functions inject the secret
only into that specific process's environment via `exec`. It never appears in
`env` output, shell history, or any other process's environment.

### Why Claude Code uses apiKeyHelper (not a wrapper script)

Claude Code natively supports `apiKeyHelper` in `~/.claude/settings.json`.
It calls the specified command to fetch the API key, auto-refreshes every
5 minutes, and retries on HTTP 401. This is strictly better than a wrapper:
- No binary collision issues (the real `claude` binary is on PATH)
- Built-in refresh logic
- Works with Claude Code's internal update mechanisms

### Why gh uses a shell function (not a wrapper script)

`programs.gh` (home-manager module) provides the `gh` binary and configures
`gitCredentialHelper`, which makes gh serve as git's credential helper. A
`writeShellScriptBin "gh"` wrapper would collide with the binary installed
by `programs.gh`, causing a Nix build failure (two packages providing
`/bin/gh`). A zsh function shadows the binary at shell level without
collision:

```zsh
gh() { GITHUB_TOKEN=$(rbw get github-token) command gh "$@"; }
```

This also replaces `credential.helper = "store"` (plaintext
`~/.git-credentials`) with gh-based OAuth credential resolution.

### Why the age public key comes from the VM (not the Mac)

sops encryption is asymmetric. The **public key** encrypts; the **private
key** decrypts. The VM owns a dedicated sops age key at
`/var/lib/sops-nix/key.txt`:

- **Public key** → stored in `sops.hostPubKey` in the repo. Used by
  `collect-secrets` on the Mac to encrypt. Safe to commit publicly —
  it reveals nothing about the private key.
- **Private key** → stays on the VM. Used by sops-nix at boot to decrypt
  `/run/secrets/*`. Never leaves the VM.

The Mac doesn't decrypt anything. It only encrypts.

## Files involved

| File | Role |
|------|------|
| `flake.nix` | Inputs: `sops-nix`, `sopsidy`. Output: `packages.aarch64-darwin.collect-secrets`. |
| `lib/mksystem.nix` | Wires `sops-nix.nixosModules.sops` and `sopsidy.nixosModules.default` into all non-darwin systems. |
| `machines/vm-shared.nix` | `sops.hostPubKey`, `sops.defaultSopsFile`, `sops.age.keyFile`, `sops.age.generateKey`, secret declarations for `tailscale/auth-key`, `rbw/master-password`, `rbw/email`, and `uniclip/password`. |
| `machines/secrets.yaml` | Age-encrypted YAML generated by `collect-secrets`. **Gitignored** (defense-in-depth); force-added on the VM by Makefile targets so the flake can see it. |
| `users/m/nixos.nix` | `systemd.user.services.rbw-config`: writes rbw config from sops email. `rbw-unlock`: auto-unlocks rbw on login (depends on rbw-config). |
| `users/m/home-manager.nix` | `programs.gh` with credential helper, wrapper scripts for codex/sentry-cli, Claude Code `apiKeyHelper`, `gh()` shell function, `with-openai`/`with-amp` aliases. (rbw binary installed via `home.packages`; config NOT Nix-managed.) |
| `Makefile` | `secrets/collect`, `vm/age-key` targets. |

## Bitwarden vault entries

These entries must exist in Bitwarden (names are exact matches for `rbw get`):

| Entry name | Used by | Delivery |
|------------|---------|----------|
| `bitwarden-email` | sopsidy → sops → rbw-config systemd service | sops (boot-time) |
| `bitwarden-master-password` | sopsidy → sops → rbw-unlock systemd service | sops (boot-time) |
| `tailscale-auth-key` | sopsidy → sops → tailscale service | sops (boot-time) |
| `uniclip-password` | sopsidy → sops → uniclip user service | sops (boot-time) |
| `github-token` | `gh()` shell function | rbw (runtime) |
| `claude-oauth-token` | Claude Code `apiKeyHelper` | rbw (runtime) |
| `openai-api-key` | codex wrapper, `with-openai` alias | rbw (runtime) |
| `amp-api-key` | `with-amp` alias | rbw (runtime) |
| `sentry-auth-token` | sentry-cli wrapper | rbw (runtime) |

## Workflows

### Initial setup (one-time)

```bash
# 1. Boot/install VM once so /var/lib/sops-nix/key.txt exists (or can be created)
# 2. Get (or create) the VM's dedicated age public key
make vm/age-key
# 3. Put it in machines/vm-shared.nix → sops.hostPubKey = "age1..."

# 4. Populate Bitwarden vault with all entries listed above

# 5. Configure rbw on macOS (keeps email out of public repo)
rbw config set email your-bitwarden-email@example.com
rbw config set base_url https://api.bitwarden.eu  # if using EU instance

# 6. Encrypt secrets and deploy
make secrets/collect
make vm/copy && make vm/switch

# 7. On the VM: register rbw with Bitwarden (one-time)
ssh m@<VM_IP>
rbw register
rbw login
# Subsequent reboots auto-unlock via systemd service
```

### Rotating a secret

```bash
# On macOS:
rbw remove old-entry && echo "new-value" | rbw add old-entry

# If the secret goes through sops (tailscale, rbw master password):
make secrets/collect
make vm/copy && make vm/switch

# If the secret goes through rbw only (github-token, etc.):
# Nothing else needed — next invocation fetches the new value.
```

### Adding a new secret

For a new app that needs a token:

1. Add the entry to Bitwarden: `echo "token-value" | rbw add "myapp-token"`

2a. **If it's a system service** (needs to be available at boot):
```nix
# machines/vm-shared.nix
sops.secrets."myapp/token" = {
  collect.rbw.id = "myapp-token";
  owner = "myapp-user";  # optional
};
```
Then `make secrets/collect && make vm/copy && make vm/switch`.

2b. **If it's a user app** (interactive):
```nix
# users/m/home-manager.nix — add a wrapper script:
(pkgs.writeShellScriptBin "myapp" ''
  MYAPP_TOKEN=$(${pkgs.rbw}/bin/rbw get "myapp-token") \
    exec ${pkgs.myapp}/bin/myapp "$@"
'')
```
Then `make vm/copy && make vm/switch`. No `secrets/collect` needed.

### Rebuilding the VM from scratch

```bash
make vm/create           # create fresh VM
make vm/bootstrap0       # partition + install
make vm/bootstrap        # full config
make vm/copy             # copy config (includes secrets.yaml)
make vm/switch           # apply
ssh m@<VM_IP>
rbw register && rbw login  # one-time rbw setup
```

## Platform differences

| | macOS (darwin) | NixOS VM (linux) |
|---|---|---|
| Password manager | 1Password GUI + CLI | rbw (Bitwarden, config via sops) |
| API keys (AMP, OpenAI) | `op://` refs in sessionVariables | `with-amp`, `with-openai` shell aliases via rbw |
| gh authentication | bare `gh` binary (manual `gh auth login`) | `gh()` shell function injecting GITHUB_TOKEN from rbw |
| Claude Code | bare binary (manual auth) | `apiKeyHelper` in `~/.claude/settings.json` calling rbw |
| codex, sentry-cli | bare binaries in PATH | `writeShellScriptBin` wrappers injecting from rbw |
| Git credentials | `programs.gh.gitCredentialHelper` | `programs.gh.gitCredentialHelper` (same) |
| sops-nix | not loaded (darwin) | loaded via `mksystem.nix` |

## Dependencies

```
Bitwarden cloud service
  └── rbw (client, talks to Bitwarden API)
        ├── rbw-agent (background daemon, holds keys in memory)
        └── pinentry-tty (for interactive unlock; bypassed by systemd service)

sops (encryption tool)
  └── age (encryption backend)

sops-nix (NixOS module)
  ├── Decrypts machines/secrets.yaml at boot
  ├── Writes to /run/secrets/* (tmpfs, never on disk)
  └── Uses /var/lib/sops-nix/key.txt as age identity

sopsidy (sops-nix extension)
  ├── Adds collect.rbw.id option to sops.secrets.*
  ├── Adds sops.hostPubKey option
  ├── buildSecretsCollector → collect-secrets script
  └── rbw plugin (built-in)

programs.gh (home-manager)
  └── gitCredentialHelper → gh serves as git credential backend

programs.rbw (home-manager)
  └── Generates ~/.config/rbw/config.json
```

## Shortcomings

### `make vm/secrets` copies host private keys

The `vm/secrets` target rsyncs `~/.ssh/` and `~/.gnupg/` (including private
keys) from the Mac to the VM. This enables git push/signing from the VM,
but means a VM compromise exposes the host's SSH and GPG private keys.

**Alternatives** (for future consideration):
- SSH agent forwarding (`ssh -A`) instead of copying keys
- Dedicated deploy keys per service (GitHub, etc.)
- `gpg-agent` forwarding over SSH

### rbw auto-unlock is still stdin-driven

The `rbw-unlock` systemd service unlocks rbw by redirecting the
sops-decrypted password file into `rbw unlock`. This is still less robust
than fully interactive pinentry, so a future rbw behavior change could break
it.

**Mitigation**: a periodic timer re-runs unlock if needed. Check status with
`systemctl --user status rbw-unlock.service rbw-unlock-refresh.timer`.

### `/proc/PID/environ` leakage

Wrapper scripts and the `gh()` shell function set environment variables on
the target process. These are readable via `/proc/<PID>/environ` by any
process running as the same UID (user `m`). On a single-user VM this is
acceptable. On a shared system it would be a concern.

**More secure alternatives** (for future consideration):
- `systemd LoadCredential` for services (credentials directory in
  unswappable memory, auto-destroyed)
- Applications reading secret files directly instead of env vars
- `BindReadOnlyPaths` for sandboxed services

### Bitwarden master password is stored in sops

The master password to the entire Bitwarden vault is stored in
`machines/secrets.yaml` and decrypted to `/run/secrets/rbw/master-password`
on every boot. If an attacker gains root on the VM, they get the master
password and thereby access to every secret in the vault.

**Mitigations**:
- The file is `mode=0400 owner=m` (not world-readable).
- `/run/secrets` is tmpfs (not persisted to disk).
- The VM's age private key (`/var/lib/sops-nix/key.txt`) is the only
  thing that can decrypt `secrets.yaml`. Compromising the Mac alone is not
  sufficient.

**Alternative**: use a Bitwarden API key or service account instead of the
master password. This scopes access and can be revoked without changing the
master password.

### Tailscale auth key expiry

Tailscale pre-auth keys expire after 90 days by default. If the key in
Bitwarden expires and you reboot the VM, tailscale will fail to authenticate.

**Mitigation**: use a **reusable, tagged** auth key in the Tailscale admin
panel and disable node key expiry for the tag.

### `.claude/settings.json` is fully managed

The `home.file.".claude/settings.json"` entry overwrites the entire file.
If Claude Code or the user adds other settings to this file, they will be
lost on next `home-manager switch`. To preserve additional settings, extend
the `builtins.toJSON` block in `home-manager.nix`.

### One-time rbw bootstrap on fresh VM

After a fresh VM install, `rbw register` and `rbw login` must be run
manually (interactive, requires master password + 2FA if enabled). The
`rbw-unlock` systemd service only handles `rbw unlock`, not the initial
registration. This is inherent to Bitwarden's security model — device
registration cannot be fully automated.

### sopsidy chicken-and-egg

The `bitwarden-master-password` entry in Bitwarden is the master password
to Bitwarden itself. To collect it, rbw must already be unlocked on the Mac.
If you lose access to all authenticated rbw sessions simultaneously, you
need to re-authenticate rbw manually before you can run `collect-secrets`.
This is not a real risk in practice (the Mac stays authenticated), but it's
worth understanding the dependency.

## Security model summary

```
Who can decrypt secrets.yaml?
  → Only the VM (via /var/lib/sops-nix/key.txt → age private key)

Who can read /run/secrets/* on the VM?
  → root (all secrets)
  → user m (only rbw/master-password, via owner=m mode=0400)

Who can access Bitwarden vault?
  → Anyone with the master password + registered device
  → On the VM: the rbw-unlock service (automated)
  → On the Mac: manual rbw unlock or 1Password GUI

What's in the git repo (public)?
  → age public key (safe: encryption only, reveals nothing)
  → SSH public key for host-authorized-keys (safe: public key, authorizes host on VM)
  → SSH public key for mac-host-authorized-keys (safe: public key, authorizes VM→host Docker-over-SSH)

What's NOT in the git repo?
  → machines/secrets.yaml (gitignored; defense-in-depth)
  → Bitwarden email (delivered via sops on VM, local file on Mac)
  → Any plaintext secret
  → The VM's age private key (`/var/lib/sops-nix/key.txt`)
  → The Bitwarden master password (only encrypted form)
```
