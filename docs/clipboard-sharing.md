# Clipboard Sharing (macOS ↔ NixOS VM)

Clipboard is shared between the macOS host and the NixOS VM using a patched
build of [uniclip](https://github.com/quackduck/uniclip) over a direct TCP
connection. VMware Fusion's built-in clipboard was abandoned because its
GTK3/X11 plugin does not work under the VM's Wayland desktop.

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

- The macOS server binds to `192.168.130.1:53701`.
- The VM client connects directly to `192.168.130.1:53701`.
- Both sides use `--secure`; the password is sourced from Bitwarden on macOS
  and from a boot-time sops secret on the VM.
- No SSH tunnel is involved anymore.

## Where the configuration lives

| File | Role |
|------|------|
| `patches/uniclip-bind-and-env-password.patch` | Adds `--bind` and `UNICLIP_PASSWORD` support to uniclip |
| `flake.nix` | Builds the patched `pkgs.uniclip` package from `uniclip-src` |
| `den/aspects/features/launchd.nix` | macOS launchd user agent for the uniclip server |
| `den/aspects/features/vmware.nix` | VM Home Manager `systemd.user.services.uniclip` client |
| `den/aspects/features/secrets.nix` | Declares `/run/secrets/uniclip/password` on the VM |

## macOS side

The server is defined in `den/aspects/features/launchd.nix`.

Behavior:
- waits for `/nix/store` to exist
- fetches the password with `rbw get uniclip-password`
- exports `UNICLIP_PASSWORD`
- starts `uniclip --secure --bind 192.168.130.1 -p 53701`
- restarts automatically via launchd if it exits
- logs to `/tmp/uniclip-server.log`

## VM side

The client is defined in `den/aspects/features/vmware.nix`.

Behavior:
- starts after `graphical-session.target`
- detects an available Wayland socket (`wayland-1` or `wayland-0`)
- reads `/run/secrets/uniclip/password`
- exports `UNICLIP_PASSWORD`
- starts `uniclip --secure 192.168.130.1:53701`
- restarts on failure after 5 seconds

## Password management

The shared encryption password is stored in Bitwarden under
`uniclip-password`.

- **macOS:** fetched live by the launchd agent through `rbw`
- **VM:** collected into the external generated dataset
  (`~/.local/share/nix-config-generated` on macOS, mounted as `/nixos-generated`
  in the VM), decrypted by sops-nix, and exposed as
  `/run/secrets/uniclip/password`

## Debugging

```bash
# macOS — check the launchd agent:
launchctl list | grep uniclip

# macOS — tail logs:
tail -f /tmp/uniclip-server.log

# VM — check the user service:
systemctl --user status uniclip

# VM — tail logs:
journalctl --user -u uniclip -f

# VM — verify connectivity to the host:
nc -zv 192.168.130.1 53701

# VM — confirm Wayland clipboard plumbing:
WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 wl-paste
```
