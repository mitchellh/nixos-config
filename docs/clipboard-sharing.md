# Clipboard Sharing (macOS  NixOS VM)

Clipboard is shared between the macOS host and NixOS VM using a patched build
of [uniclip](https://github.com/quackduck/uniclip) over direct TCP connection.
VMware Fusion's built-in clipboard was abandoned — it uses a GTK3/X11 plugin
(`libdndcp.so`) that does not work under Wayland.

## Architecture

```
macOS (host)                              NixOS VM (guest)
┌──────────────────────┐                 ┌──────────────────────┐
│ uniclip server       │                 │ uniclip client       │
│ --secure             │                 │ --secure             │
│ --bind 192.168.130.1 │◄────────────────│ 192.168.130.1:53701  │
│ -p 53701             │   (direct TCP)  │                      │
│ UNICLIP_PASSWORD=... │                 │ UNICLIP_PASSWORD=... │
│ (from rbw)           │                 │ (from sops)          │
└──────────────────────┘                 └──────────────────────┘
```

- macOS uniclip server binds to `192.168.130.1:53701` (VMware host network on bridge101)
- VM uniclip client connects directly to `192.168.130.1:53701`
- Both sides use `--secure` (AES-GCM encryption); shared password from Bitwarden
- **No SSH tunnel needed** - direct connection is simpler and more reliable

## Uniclip patch

Uniclip upstream (`patches/uniclip-bind-and-env-password.patch`) was patched to add:

- `--bind/-b` flag: server binds to `bindAddr:port` instead of always `0.0.0.0:port`
- `UNICLIP_PASSWORD` env var: read password from environment before falling back to
  interactive `terminal.ReadPassword` (which requires a TTY — incompatible with launchd/systemd)
- Max args bumped from 4 to 8 to accommodate the new flags

Built from source as a `buildGoModule` in `flake.nix`: non-flake `uniclip-src` input + overlay entry.

## macOS side

One launchd user agent managed by nix-darwin in `users/m/darwin.nix`:

**`org.nixos.uniclip`** — uniclip server:
- Waits for `/nix/store` to be available (`/bin/wait4path`)
- Fetches password via `rbw get uniclip-password`
- Binds to `192.168.130.3:53701` (VMware private network interface)
- Starts `uniclip --secure --bind 192.168.130.3 -p 53701`
- `KeepAlive = true` (launchd restarts on exit)
- Logs to `/tmp/uniclip-server.log`

## VM side

A systemd user service in `users/m/home-manager.nix`:

**`uniclip.service`** — uniclip client:
- Starts after `graphical-session.target` (Wayland must be up)
- Reads password from `/run/secrets/uniclip/password` (sops-nix managed)
- Sets `WAYLAND_DISPLAY=wayland-1` and `XDG_RUNTIME_DIR=/run/user/$(id -u)`
- Connects directly to `192.168.130.3:53701` (no SSH tunnel)
- `Restart=on-failure`, `RestartSec=5`

## Password management

The shared encryption password is stored in Bitwarden and managed differently on each side:

**macOS:** Fetches from Bitwarden via `rbw` at service startup.

**VM:** Password stored in sops secrets (`/run/secrets/uniclip/password`), managed by sops-nix.

One-time setup:
```bash
# On macOS (generates and saves to Bitwarden):
rbw generate --no-symbols 32 uniclip-password

# Store in sops for VM access (in your secrets.yaml):
# uniclip:
#   password: <the-generated-password>

# On VM (after sops secrets are deployed):
systemctl --user restart uniclip
```

## Files

| File | Role |
|------|------|
| `patches/uniclip-bind-and-env-password.patch` | Go patch adding `--bind` and `UNICLIP_PASSWORD` |
| `flake.nix` | `uniclip-src` non-flake input + `uniclip` buildGoModule overlay |
| `users/m/darwin.nix` | launchd agent: `uniclip` (server) |
| `users/m/home-manager.nix` | `pkgs.uniclip` package + `systemd.user.services.uniclip` (VM client) |

## Debugging

```bash
# macOS — check agent is running:
launchctl list | grep uniclip

# macOS — tail logs:
tail -f /tmp/uniclip-server.log

# VM — check service:
systemctl --user status uniclip

# VM — tail logs:
journalctl --user -u uniclip -f

# VM — manual test paste:
WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 wl-paste

# VM — test connectivity to macOS:
nc -zv 192.168.130.3 53701
```
