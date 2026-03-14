# Secrets Management

This repository uses a hybrid model:

- **sops-nix + sopsidy** for boot-time VM secrets
- **rbw (Bitwarden)** for runtime user-facing secrets

The repository is now den-native, so the moving pieces live in den aspects
rather than legacy machine/user entrypoints.

## Architecture overview

```
macOS host
  Bitwarden vault
    └── rbw
          └── WRAPPER=$(bash scripts/external-input-flake.sh)
                nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file
                └── ~/.local/share/nix-config-generated/secrets.yaml (age-encrypted, outside the repo)
                      └── bash docs/vm.sh switch

NixOS VM
  /nixos-generated (VMware shared folder exposing the same dataset)
    └── flake input `generated`
          └── sops-nix decrypts secrets.yaml
                ├── /run/secrets/tailscale/auth-key
                ├── /run/secrets/rbw/email
                ├── /run/secrets/uniclip/password
                └── /run/secrets/user/hashed-password

  den/aspects/features/secrets.nix
    ├── services.tailscale.authKeyFile
    ├── users.users.m.hashedPasswordFile
    └── systemd.user.services.rbw-config

  den/aspects/features/shell-git.nix
    ├── gh()        -> rbw get github-token
    ├── with-openai -> rbw get openai-api-key
    ├── with-amp    -> rbw get amp-api-key
    ├── claude      -> rbw get claude-oauth-token
    └── codex       -> rbw get openai-api-key
```

## What goes through sops vs rbw

| Secret | Delivery | Why |
|--------|----------|-----|
| `rbw/email` | sops → file → `rbw-config` | Keeps the Bitwarden email out of the public repo while still generating the VM rbw config automatically. |
| `tailscale/auth-key` | sops → file → Tailscale service | Needed by a system service before the user session exists. |
| `uniclip/password` | sops → file → VM uniclip service | Needed by the VM clipboard client at user-session startup. |
| `user/hashed-password` | sops → file → `users.users.m.hashedPasswordFile` | Needed during system activation, not interactively. |
| `github-token` | rbw → shell function | Fetched on demand by `gh()`. |
| `claude-oauth-token` | rbw → shell function | Injected only for `claude`. |
| `openai-api-key` | rbw → shell functions | Used by `codex` and `with-openai`. |
| `amp-api-key` | rbw → shell function | Used by `with-amp`. |

Rule of thumb: if the secret is needed during boot or activation, it goes
through sops; otherwise it is fetched live from Bitwarden.

## Where the configuration lives

| File | Role |
|------|------|
| `flake.nix` | Declares shared inputs and exports `lib.mkOutputs` for wrapper flakes |
| `den/mk-config-outputs.nix` | Builds system outputs plus the `collect-secrets` package once external inputs are provided |
| `scripts/external-input-flake.sh` | Creates a temporary wrapper flake with the live generated / yeet-and-yoink inputs |
| `den/aspects/features/secrets.nix` | Owns secret declarations, Tailscale auth, hashed password wiring, `rbw-config`, and `generated.requireFile "secrets.yaml"` |
| `den/aspects/features/home-base.nix` | Owns Linux `programs.rbw` settings |
| `den/aspects/features/shell-git.nix` | Owns runtime rbw-backed shell helpers (`gh`, `claude`, `codex`, `with-openai`, `with-amp`) |
| `den/aspects/hosts/vm-aarch64.nix` | Reads the VM age public key from the generated input via `sops.hostPubKey` |
| `~/.local/share/nix-config-generated/` | Canonical generated dataset on macOS (`secrets.yaml`, SSH pubkeys, age pubkey) |
| `docs/vm.sh` | VM provisioning/switch helper, including `refresh-secrets` |
| `/nixos-generated` | VMware shared-folder mount exposing the same dataset inside the VM |
| `WRAPPER=$(bash scripts/external-input-flake.sh) && nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file` | Regenerates the external `secrets.yaml` dataset locally |

## Bitwarden entries

These Bitwarden item names are consumed directly by the current config:

| Entry name | Used by | Delivery |
|------------|---------|----------|
| `bitwarden-email` | `sops.secrets."rbw/email"` | sops |
| `tailscale-auth-key` | `sops.secrets."tailscale/auth-key"` | sops |
| `uniclip-password` | `sops.secrets."uniclip/password"` | sops |
| `nixos-hashed-password` | `sops.secrets."user/hashed-password"` | sops |
| `github-token` | `gh()` / git credential helper flow | rbw |
| `claude-oauth-token` | `claude()` wrapper | rbw |
| `openai-api-key` | `codex()` and `with-openai()` | rbw |
| `amp-api-key` | `with-amp()` | rbw |

## Common workflows

### Initial setup

```bash
# 1. Ensure the VM age key and generated SSH pubkeys are synced
bash docs/vm.sh refresh-secrets

# 2. Populate Bitwarden with the entries listed above

# 3. Collect and encrypt boot-time secrets into the external dataset
WRAPPER=$(bash scripts/external-input-flake.sh)
nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file

# 4. Deploy to the VM
bash docs/vm.sh switch

# 5. On the VM, register/login rbw once if needed
ssh m@<VM_IP>
rbw register
rbw login
```

### Rotating a boot-time secret

```bash
rbw remove tailscale-auth-key
echo "new-value" | rbw add tailscale-auth-key

WRAPPER=$(bash scripts/external-input-flake.sh)
nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file
bash docs/vm.sh switch
```

### Rotating a runtime secret

```bash
rbw remove github-token
echo "new-value" | rbw add github-token

# No rebuild needed; next helper invocation fetches the new value.
```

### Adding a new boot-time secret

Declare it in `den/aspects/features/secrets.nix`:

```nix
sops.secrets."myapp/token" = {
  collect.rbw.id = "myapp-token";
  owner = "myapp-user";
};
```

Then run:

```bash
WRAPPER=$(bash scripts/external-input-flake.sh)
nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file
bash docs/vm.sh switch
```

### Adding a new runtime secret helper

Add the Bitwarden entry:

```bash
echo "token-value" | rbw add myapp-token
```

Then add the helper to the relevant den aspect (usually
`den/aspects/features/shell-git.nix` or another user-facing feature aspect).

## Security notes

### Why runtime helpers use shell functions

The current setup injects secrets only into the target process:

- `gh()` sets `GITHUB_TOKEN` for the `gh` invocation
- `claude()` sets `CLAUDE_CODE_OAUTH_TOKEN`
- `codex()` and `with-openai()` set `OPENAI_API_KEY`
- `with-amp()` sets `AMP_API_KEY`

This keeps secrets out of global login-session variables, but they are still
visible to processes running as the same user through `/proc/<PID>/environ`.

### Why the age public key comes from the VM

The VM owns the age private key at `/var/lib/sops-nix/key.txt`. The matching
public key is stored in the external generated dataset as `vm-age-pubkey` and read by
`den/aspects/hosts/vm-aarch64.nix` as `sops.hostPubKey`.

- The Mac uses the public key only to encrypt.
- The VM keeps the private key and is the only system that can decrypt
  `secrets.yaml`.

### Known trade-off: copied host keys

The VM SSH/Docker workflow expects suitable key material to exist inside the VM
(for example `~/.ssh/id_ed25519` for the `mac-host-docker` SSH config). That is
convenient for Docker-over-SSH and git workflows, but it also means any private
keys present in the VM are exposed if the VM is compromised.

## Security model summary

```text
Who can decrypt secrets.yaml from the generated dataset?
  -> Only a host with the matching age private key (the VM)

Who can read /run/secrets/* on the VM?
  -> root
  -> user m for the secrets explicitly owned by m

What is stored in the repo?
  -> declarative secret wiring
  -> secret names / IDs
  -> no plaintext secrets

What is not stored in the repo?
  -> ~/.local/share/nix-config-generated/secrets.yaml
  -> ~/.local/share/nix-config-generated/{vm-age-pubkey,host-authorized-keys,mac-host-authorized-keys}
  -> the VM age private key
  -> Bitwarden runtime secrets
```
