# AGENTS.md - NixOS System Configurations

This document provides essential context for AI agents working on this NixOS/nix-darwin system configuration repository.

## Project Overview

This is a **NixOS/nix-darwin system configuration repository** that manages complete system configurations for multiple machines and environments using the Nix language.

**Supported Platforms:**
- **NixOS VM** (primary) - Linux development environment running on macOS host via VMware Fusion
- **macOS** - Host system configuration via nix-darwin
- **WSL** - Windows Subsystem for Linux for Windows environments

**Philosophy:** Use macOS for graphical applications (browser, messaging, etc.) and NixOS VM for all development work. A single codebase configures all three platforms with appropriate conditional logic.

## Multi-Platform Architecture

### How It Works

The repository is now built around **den**.

- `flake.nix` exports `lib.mkOutputs`, a wrapper-friendly entrypoint that
  accepts external `generated` / `yeetAndYoink` inputs without committing fake
  sentinel paths.
- `scripts/external-input-flake.sh` materialises a temporary wrapper flake in
  `$TMPDIR` and points it at this checkout plus the live external inputs.
- `den/mk-config-outputs.nix` contains the real output builder and returns
  `inherit (den.flake) nixosConfigurations darwinConfigurations;`.
- `den/default.nix` imports `inputs.den.flakeModule` and wires shared host/user
  context.
- `den/hosts.nix` declares the concrete hosts (`vm-aarch64`, `macbook-pro-m1`,
  `wsl`) and their metadata.

```
flake.nix
  │
  └── exports lib.mkOutputs

scripts/external-input-flake.sh
  │
  └── creates a temp wrapper flake with generated / yeetAndYoink inputs

den/mk-config-outputs.nix
  ├── imports ./default.nix
  ├── imports ./hosts.nix
  ├── imports ./aspects/
  └── inherit (den.flake) nixosConfigurations darwinConfigurations

den/hosts.nix
  ├── den.hosts.aarch64-linux.vm-aarch64
  ├── den.hosts.aarch64-darwin.macbook-pro-m1
  └── den.hosts.x86_64-linux.wsl
```

### Platform Detection Mechanism

den aspects close over host metadata directly:

```nix
({ host, ... }:
  let
    isDarwin = host.class == "darwin";
    isLinux = host.class == "nixos";
    isWSL = host.wsl.enable or false;
    isVM = host.vmware.enable or false;
    isGraphical = host.graphical.enable or false;
  in { ... })
```

These flags are then threaded into `nixos`, `darwin`, and `homeManager`
submodules inside each aspect.

### Conditional Configuration Patterns

**In den feature aspects** — derive booleans from `host`:
```nix
({ host, ... }:
  let
    isDarwin = host.class == "darwin";
    isLinux = host.class == "nixos";
    isWSL = host.wsl.enable or false;
  in {
    homeManager = { pkgs, lib, ... }: {
      home.packages = []
        ++ (lib.optionals isDarwin [ pkgs.mac-only ])
        ++ (lib.optionals (isLinux && !isWSL) [ pkgs.gui-linux-only ]);
    };
  })
```

**For host-specific overrides** — attach them in `den/aspects/hosts/<name>.nix`:
```nix
nixos = { ... }: {
  networking.interfaces.enp2s0.useDHCP = true;
};
```

### Platform-Specific Limitations

| Platform | Limitations & Considerations |
|----------|------------------------------|
| **NixOS VM** | Requires VMware Fusion on macOS host; shared folders mount at `/host`; firewall disabled for development convenience |
| **macOS** | Uses Determinate Nix installer, so `nix.enable = false` in darwin config; Homebrew manages GUI apps via casks; some Linux-only packages unavailable |
| **WSL** | No graphical applications; builds to a tarball installer; limited systemd support; filesystem mounted at `/mnt` |

### What Each Platform Gets

| Component | VM (Linux) | macOS | WSL |
|-----------|------------|-------|-----|
| **Window Manager** | Niri/Mango (Wayland) | Native macOS | None |
| **Terminal** | Ghostty, foot | Native | Windows Terminal |
| **Package Manager** | Nix only | Nix + Homebrew | Nix only |
| **GUI Apps** | Firefox, Chromium | Via Homebrew casks | None |
| **Display Manager** | greetd + tuigreet | N/A | N/A |
| **Input Method** | fcitx5 | Native | N/A |
| **Docker** | Native | Docker Desktop | Docker Desktop |
| **Clipboard Sharing** | uniclip client (systemd) | uniclip server (launchd) | N/A |
| **Editors** | Doom Emacs (daemon), Neovim | Doom Emacs, Neovim | Neovim |

## Clipboard Sharing (Uniclip)

The macOS host and NixOS VM share a clipboard via uniclip over a direct TCP connection:

```
macOS (host)                              VM (guest)
┌──────────────────────┐                 ┌──────────────────────┐
│ uniclip server       │                 │ uniclip client       │
│ --secure             │                 │ --secure             │
│ --bind 192.168.130.1 │                 │ 192.168.130.1:53701  │
│ -p 53701             │                 │                      │
│ UNICLIP_PASSWORD=... │                 │ UNICLIP_PASSWORD=... │
│ (from rbw)           │                 │ (from sops)          │
└──────────────────────┘                 └──────────────────────┘
```

**Key details:**
- Uniclip is built from source with a custom patch (`patches/uniclip-bind-and-env-password.patch`) that adds `--bind` flag and `UNICLIP_PASSWORD` env var support
- Password stored in rbw (Bitwarden) as `uniclip-password`
- macOS side: launchd user agent in `den/aspects/features/launchd.nix`
- VM side: systemd user service in `den/aspects/features/vmware.nix`
- Full documentation in `docs/clipboard-sharing.md`

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `/den/` | den framework wiring: hosts, shared context, and reusable aspects |
| `~/.local/share/nix-config-generated/` | Canonical generated dataset on macOS: `secrets.yaml`, SSH pubkeys, and the VM age pubkey; wired into temporary wrapper flakes via `scripts/external-input-flake.sh` |
| `/modules/` | Reusable NixOS modules |
| `/modules/specialization/` | System specializations (alternative desktop environments, e.g., GNOME+ibus) |
| `/dotfiles/common/` | Shared user-owned assets consumed by den aspects (shell config, editors, OpenCode, repo-manager config) |
| `/dotfiles/by-host/darwin/` | macOS-specific user assets |
| `/dotfiles/by-host/vm/` | VM-specific user assets |
| `/dotfiles/by-host/wsl/` | WSL-specific user assets |
| `/patches/` | Source patches (uniclip bind+env password patch) |
| `/docs/` | Documentation and helper scripts (`vm.sh`, `macbook.sh`) |
| `/.github/` | GitHub workflows (GitHub Pages deployment) |

### Dotfiles Layout

| File | Purpose |
|------|---------|
| `dotfiles/common/bashrc`, `inputrc`, `gdbinit`, `zsh-manydot.sh`, `starship.toml` | Shared shell and tool configurations |
| `dotfiles/common/doom/`, `lazyvim/`, `tmux/`, `vscode/` | Shared editor and terminal assets |
| `dotfiles/common/opencode/` | OpenCode config, modules, commands, and agent/theme assets |
| `dotfiles/common/grm-repos.yaml` | Declarative git-repo-manager repo list |
| `dotfiles/by-host/darwin/skhdrc`, `wezterm.lua`, `kanata/`, `activitywatch/` | macOS-specific assets |
| `dotfiles/by-host/vm/wezterm.lua`, `ghostty.cfg`, `mangowc.cfg`, `noctalia.json` | VM-specific assets |

## Build / Bootstrap Commands

There is no checked-in Makefile. Use the helper
scripts in `docs/` plus direct Nix commands:

| Command | Description |
|---------|-------------|
| `bash docs/macbook.sh` | Bootstrap a fresh macOS host and apply the nix-darwin config |
| `bash docs/vm.sh bootstrap` | Create/install the NixOS VM and perform first-time provisioning |
| `bash docs/vm.sh switch` | Apply the current VM configuration over SSH/shared folders |
| `bash docs/vm.sh refresh-secrets` | Refresh the VM age public key, generated SSH pubkeys, and the external `secrets.yaml` dataset |
| `bash docs/vm.sh ssh` | SSH into the VM (or run a command) |
| `bash scripts/external-input-flake.sh` | Create a temporary wrapper flake for this checkout and print its path |
| `WRAPPER=$(bash scripts/external-input-flake.sh) && nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file` | Regenerate the external `secrets.yaml` dataset locally via sopsidy |
| `WRAPPER=$(bash scripts/external-input-flake.sh) && nix build "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file` | Build the Darwin system closure |
| `WRAPPER=$(bash scripts/external-input-flake.sh) && sudo ./result/sw/bin/darwin-rebuild switch --flake "path:$WRAPPER#macbook-pro-m1" --no-write-lock-file` | Apply the built Darwin system |
| `WRAPPER=$(bash scripts/external-input-flake.sh) && nix build "path:$WRAPPER#nixosConfigurations.vm-aarch64.config.system.build.toplevel" --no-write-lock-file` | Build the VM system closure |

**Environment Variables for VM Operations:**
- `NIXADDR` - Preferred VM IP address (default: `192.168.130.3`; `docs/vm.sh` also falls back through `vm_detect_ip`)
- `NIXPORT` - SSH port (default: 22)
- `NIXUSER` - Username (default: m)
- `NIXNAME` - Configuration name (default: vm-aarch64)
- `NIXINSTALLUSER` - Bootstrap SSH username during install (default: root)
- `NIX_CONFIG_DIR` - Local checkout path used by `docs/vm.sh` (default: `~/.config/nix`)
- `GENERATED_DIR` - Canonical generated dataset path on macOS (default: `~/.local/share/nix-config-generated`)
- `VM_SHARED_GENERATED_DIR` - VM mountpoint for the generated dataset (default: `/nixos-generated`)
- `HOST_SSH_PUBKEY_FILE` - Host public key copied into the generated dataset (default: `~/.ssh/id_ed25519.pub`)

## Key Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Base flake entry point - defines shared inputs and exports `lib.mkOutputs` |
| `flake.lock` | Locked versions of all flake inputs (dependencies) |
| `den/mk-config-outputs.nix` | Reusable output builder used by temporary wrapper flakes |
| `docs/macbook.sh` | Bootstrap/apply script for macOS |
| `docs/vm.sh` | VM creation, switching, secret refresh, and SSH helper |
| `scripts/external-input-flake.sh` | Sourceable/executable helper that creates a wrapper flake with live external inputs |
| `den/default.nix` | den bootstrap: flake module import, host/user context wiring, overlays, host-level modules |
| `den/hosts.nix` | Host declarations for VM, macOS, and WSL |
| `den/aspects/hosts/vm-aarch64.nix` | VM host composition and VM-specific remnants |
| `den/aspects/hosts/macbook-pro-m1.nix` | macOS host composition |
| `den/aspects/hosts/wsl.nix` | WSL host composition |
| `den/aspects/users/m.nix` | User `m` aspect aggregation |
| `patches/uniclip-bind-and-env-password.patch` | Go patch for uniclip `--bind` flag and `UNICLIP_PASSWORD` env var |

## External Dependencies (Flake Inputs)

| Input | Channel/Source | Purpose |
|-------|----------------|---------|
| `nixpkgs` | `nixos-25.11` (stable) | Primary package source |
| `nixpkgs-unstable` | unstable | Bleeding-edge packages (gh, claude-code) |
| `nixpkgs-master` | master | Testing only - extremely unstable |
| `nixpkgs-old-ibus` | pinned commit | ibus 1.5.29 testing |
| `home-manager` | nightly | User environment management (follows nixpkgs) |
| `darwin` | `nix-darwin-25.11` | macOS system management (follows nixpkgs) |
| `nixos-wsl` | - | WSL support |
| `nix-snapd` | - | Snap package support |
| `niri` | - | Scrollable-tiling Wayland compositor |
| `mangowc` | - | Wayland window control |
| `noctalia` | - | Wayland shell (follows nixpkgs-unstable) |
| `rust-overlay` | - | Rust toolchain management |
| `ghostty` | - | Terminal emulator |
| `llm-agents` | - | 70+ AI coding agent tools |
| `lazyvim` | - | Declarative Neovim + LazyVim |
| `nix-doom-emacs-unstraightened` | - | Doom Emacs via Nix (declarative, replaces manual `doom sync`) |
| `disko` | - | Declarative disk partitioning |
| `git-repo-manager` | - | Declarative git repo management |
| `sops-nix` | - | Secrets management |
| `sopsidy` | - | Secrets management (companion to sops-nix) |
| `agent-of-empires-src` | non-flake | Terminal session manager for AI agents (built from source) |
| `uniclip-src` | non-flake | Clipboard sharing tool (built from source with custom patch) |

**Channel Strategy:**
- Use `nixpkgs` (stable) for most packages - reliability over freshness
- Use `nixpkgs-unstable` when stable has bugs or you need recent features
- Define overrides in `flake.nix` overlays section, not scattered throughout configs

## Module Orchestration (den)

den composes the system in layers:

1. **`den/default.nix` host context**
   - imports `inputs.den.flakeModule`
   - applies host-level overlays for both `nixos` and `darwin`
   - wires host-side special modules (`sops-nix`, `sopsidy`, `nix-snapd`, `niri`, `disko`, `mangowc`, `noctalia`, conditional `nixos-wsl`)
2. **`den/default.nix` user context**
   - applies Home Manager overlays and `allowUnfree`
3. **`den/hosts.nix`**
   - declares host metadata (`profile`, `vmware.enable`, `graphical.enable`, `wsl.enable`)
4. **Host aspects**
   - `den/aspects/hosts/*.nix` pull together reusable feature aspects and host-specific configuration
5. **User aspects**
   - `den/aspects/users/m.nix` aggregates shared user behavior across platforms

### Important Module System Lessons

- **HM modules must be declared unconditionally**: `programs.niri`, `wayland.windowManager.mango`, `programs.noctalia-shell` — using `lib.mkIf` only guards values, not option declarations. If the module isn't loaded, the option doesn't exist.
- **Host-level overlays matter**: den-built hosts need `nixpkgs.overlays = overlays` in `den.ctx.host.includes`, not just in Home Manager, or system modules won't see overlay packages like `uniclip`.
- **`lib.optionalAttrs` with `pkgs.stdenv.isDarwin`** can still trigger infinite recursion in module structure — prefer den host metadata and `lib.mkIf`.

## Nix Patterns Used in This Codebase

### Common Idioms

```nix
# Conditional list append
packages = [ pkgs.always ] ++ (lib.optionals condition [ pkgs.sometimes ]);

# Conditional attribute set merge
config = { always = true; } // (if condition then { sometimes = true; } else {});

# lib.mkIf for module options (preferred in NixOS modules)
services.foo.enable = lib.mkIf isLinux true;

# Reading external files
home.file.".config/foo".text = builtins.readFile ./foo-config;
```

### den Host Context

In den-native aspects, derive platform/machine state from the den `host`
object rather than legacy `config._module.args` values like
`currentSystemName`:
- `host.class` - `"nixos"` or `"darwin"`
- `host.wsl.enable or false` - WSL-specific behavior
- `host.vmware.enable or false` - VMware guest behavior
- `host.profile` - repo-defined host profile (`vm`, `darwin-laptop`, `wsl`)
- `host.users.<name>` - declared users for the host

## macOS Configuration (`den/aspects/features/darwin-core.nix` + `den/aspects/features/darwin-desktop.nix`)

- `system.stateVersion = 5` (macOS Sequoia)
- `nix.enable = false` (Determinate Nix installer manages Nix)
- `nix.settings.trusted-users = ["@admin"]`
- **Touch ID sudo**: `security.pam.services.sudo_local` with `touchIdAuth = true`, `watchIdAuth = true`, `reattach = true`
- **Shells**: zsh and fish enabled, both with Nix daemon init
- **Linux builder**: Defined but disabled (`enable = false`). Config: 6 cores, 100GB disk, 32GB RAM
- `environment.systemPackages = [ cachix ]`

## macOS Homebrew Apps (`den/aspects/features/homebrew.nix`)

**Casks:** 1password, activitywatch, claude, discord, gimp, google-chrome, leader-key, lm-studio, loop, mullvad-vpn, rectangle, spotify

**Brews:** gnupg, kanata, kanata-tray

**Mac App Store:**

| App | ID |
|-----|----|
| Calflow | 6474122188 |
| Journal It | 6745241760 |
| Noir | 1592917505 |
| Perplexity | 6714467650 |
| Tailscale | 1475387142 |
| Telegram | 747648890 |
| Vimlike | 1584519802 |
| Wblock | 6746388723 |

## Debugging and Troubleshooting

### Useful Commands

```bash
WRAPPER=$(bash scripts/external-input-flake.sh)

# Evaluate a specific configuration without building
nix eval "path:$WRAPPER#nixosConfigurations.vm-aarch64.config.networking.hostName"

# Open a REPL with the flake loaded
nix repl "path:$WRAPPER#nixosConfigurations.vm-aarch64"

# Check flake for errors
nix flake check "path:$WRAPPER"

# Show what would be built/changed
nixos-rebuild dry-run --flake "path:$WRAPPER#vm-aarch64" --no-write-lock-file

# Build without switching (outputs to ./result)
nixos-rebuild build --flake "path:$WRAPPER#vm-aarch64" --no-write-lock-file

# Show derivation details
nix derivation show "path:$WRAPPER#nixosConfigurations.vm-aarch64.config.system.build.toplevel"

# List available outputs
nix flake show "path:$WRAPPER"
```

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `error: attribute 'X' missing` | Typo in option name or missing import | Check spelling; verify the module providing the option is imported |
| `infinite recursion encountered` | Circular dependency in config | Avoid referencing `config` in the same expression that defines it; use `lib.mkIf`. Do NOT use `lib.optionalAttrs` with `pkgs.stdenv.isDarwin` for module structure. |
| `collision between X and Y` | Two packages provide the same file | Use `lib.hiPrio` or remove one package |
| `hash mismatch in fixed-output derivation` | Upstream source changed | Run `nix flake update` or update the hash |
| `experimental feature 'flakes' is disabled` | Nix not configured for flakes | Ensure `experimental-features = nix-command flakes` is set |
| `Existing file would be clobbered` | home-manager dotfile conflict | Move/back up the existing file, or add a `backupFileExtension` in the den/Home Manager wiring if you want automatic backups |
| HM option `programs.X` not found | Module not loaded in den wiring | Import the module that declares the option from the relevant den aspect or `den.ctx.*.includes` |
| Niri double-declaration on Linux | niri NixOS module already registers HM options | Don't separately import the niri HM module on Linux host paths |

### Platform-Specific Debugging

**VM not getting IP:**
```bash
# Check VMware vmnet
sudo /Applications/VMware\ Fusion.app/Contents/Library/vmnet-cli --status

# Get VM IP manually via vmrun
vmrun getGuestIPAddress "/path/to/NixOS 25.11 aarch64.vmx" -wait
```

**Darwin rebuild fails:**
```bash
# Check if nix-daemon is running (Determinate installer)
launchctl list | grep nix

# Build and apply directly
WRAPPER=$(bash scripts/external-input-flake.sh)
nix build "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file
sudo ./result/sw/bin/darwin-rebuild switch --flake "path:$WRAPPER#macbook-pro-m1" --no-write-lock-file
```

**Helper script PATH issues:**
- `home.sessionPath` only affects login shells, not non-login script execution
- `docs/vm.sh` exports the VMware Fusion CLI directory onto `PATH` itself

## Common Tasks for AI Agents

### Adding a New Package

1. **Determine scope:**
   - System-wide (all users): a host or feature aspect under `den/aspects/hosts/` or `den/aspects/features/`
   - User-only: a user feature aspect included from `den/aspects/users/m.nix`

2. **Consider platform:**
   ```nix
   home.packages = [
     pkgs.cross-platform
   ] ++ (lib.optionals isDarwin [ pkgs.mac-only ])
     ++ (lib.optionals (isLinux && !isWSL) [ pkgs.gui-linux-only ]);
   ```

3. **macOS GUI apps**: Add to `den/aspects/features/homebrew.nix` (`homebrew.casks`, `brews`, or `masApps`)

4. **Test:** use the relevant helper script or a direct Nix build with the required external inputs (for example the commands in **Build / Bootstrap Commands**)

5. **Remember:** New files must be `git add`ed before building — Nix flakes only see tracked files in dirty git trees.

### Modifying Shell Configuration

- **Aliases:** Edit `den/aspects/features/shell-git.nix`
- **Zsh settings:** Edit `den/aspects/features/shell-git.nix`
- **Zsh init:** Edit `den/aspects/features/shell-git.nix` (platform-conditional blocks for brew shellenv, rbw wrappers, etc.)
- **Bash settings:** Edit `programs.bash` or `dotfiles/common/bashrc`

### Adding a New Machine

1. Add a host declaration in `den/hosts.nix`
2. Create or extend `den/aspects/hosts/<name>.nix`
3. Reuse or add feature aspects under `den/aspects/features/`
4. If needed, keep host-only hardware/disk details in the host aspect itself and use wrapper-backed tooling (for example `WRAPPER=$(bash scripts/external-input-flake.sh) && disko --flake "path:$WRAPPER#<host>"`) instead of reviving a separate `machines/` tree
5. Follow the existing host declaration pattern:
   ```nix
   den.hosts.x86_64-linux.example.profile = "vm";
   den.hosts.x86_64-linux.example.users.m = { };
   ```

### Updating Dependencies

```bash
# Update all inputs
nix flake update

# Update a specific input
nix flake lock --update-input nixpkgs
```

### Using Specializations

Specializations provide alternative boot configurations (e.g., GNOME instead of Niri):

```bash
# At boot, greetd shows available sessions
# Or switch to a specialization:
WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=/nixos-generated bash /nixos-config/scripts/external-input-flake.sh)
sudo nixos-rebuild switch --flake "path:$WRAPPER#vm-aarch64" --specialisation gnome-ibus --no-write-lock-file
```

### Secrets Management

- **rbw (Bitwarden):** Used for runtime secrets on Linux (API keys, tokens, passwords)
- **sops-nix + sopsidy:** Used for declarative secrets in NixOS configurations
- API keys are injected per-process via shell functions and wrapper scripts, NOT as global env vars
- `WRAPPER=$(bash scripts/external-input-flake.sh) && nix run "path:$WRAPPER#collect-secrets" --no-write-lock-file` collects sopsidy secrets into the external dataset; `bash docs/vm.sh refresh-secrets` refreshes VM age/pubkey material

## Desktop Environment (Linux VM)

- **Primary:** Niri (scrollable-tiling Wayland compositor) or Mango
- **Shell:** Noctalia (with user templates, Emacs theme integration, nvim matugen template)
- **Display Manager:** greetd with tuigreet
- **Terminal:** Ghostty, foot
- **Screenshots:** grim + slurp

## Development Tooling

- **Shell:** zsh with starship prompt, atuin (history), direnv
- **Editors:** Doom Emacs (Nix-managed via `nix-doom-emacs-unstraightened`, runs as systemd daemon on Linux), Neovim (nightly via LazyVim)
- **Languages:** Rust (latest stable via overlay, with rust-src + rust-analyzer), Go, Python 3.12 + uv, Node.js 22 + fnm
- **VCS:** Git (with GPG signing, key `247AE5FC6A838272`, user `smallstepman`), programs.gh
- **AI Tools:** claude-code, codex, 70+ agents from llm-agents.nix (amp, crush, droid, forge, gemini-cli, opencode, etc.)
- **Secrets:** rbw (Bitwarden) on Linux, 1password-cli on macOS

## Doom Emacs Configuration (`dotfiles/common/doom/`)

Doom Emacs is managed declaratively via `nix-doom-emacs-unstraightened`:
```nix
programs.doom-emacs = {
  enable = true;
  doomDir = ./doom;
  emacs = pkgs.emacs-pgtk;
  tangleArgs = "--all config.org";
};
```

This replaces the old approach of symlinking `./doom` to `~/.config/doom` and running `doom sync` manually.

**Key modules enabled:** company, vertico, evil, treemacs, lsp (+eglot), magit (+forge), tree-sitter, direnv, docker, terraform, vterm

**Languages:** emacs-lisp, json, javascript (+lsp), markdown, python (+pyright), rust (+lsp +tree-sitter), sh (+lsp), web (+lsp), yaml

**Notable packages:** gptel (AI via GPT-4o-mini), git-link, git-timemachine, powerthesaurus, string-inflection, ruff-format, flymake-ruff

**Keybindings:** Colemak layout throughout. Yabai/Aerospace integration for macOS window management.

**Emacs service:** `services.emacs.enable = true` on Linux (systemd user service for Emacs daemon).

## Custom Launchd Services (macOS)

**Nix-managed (`den/aspects/features/launchd.nix` + `dotfiles/common/opencode/modules/darwin.nix`):**

| Label | Purpose |
|-------|---------|
| `org.nixos.uniclip` | Uniclip server (encrypted clipboard sharing, `192.168.130.1:53701`) |
| `org.nixos.openwebui` / `org.nixos.openwebui-tunnel` | Open WebUI plus VM-facing SSH reverse tunnel |
| `org.nixos.activitywatch-*` | ActivityWatch automation and VM-facing tunnel |
| `org.nixos.opencode-serve` / `org.nixos.opencode-web` | OpenCode background services |

**Manually managed (~/Library/LaunchAgents/):**

| Label | Purpose |
|-------|---------|
| `com.koekeishiya.yabai` | Yabai tiling window manager |
| `com.koekeishiya.skhd` | skhd hotkey daemon |
| `com.user.kanata-tray` | Kanata tray (keyboard remapper GUI) |
| `homebrew.mxcl.emacs-plus@30` | Emacs daemon (`--fg-daemon`) |
| `git.acsandmann.rift` | Rift AI code tool |
| `homebrew.mxcl.apple-music-discord-rpc` | Apple Music Discord presence |
| `homebrew.mxcl.jackett` | Jackett torrent indexer proxy |
| `com.user.bucketize-aw-and-sync-to-calendar` | ActivityWatch → Calendar sync (15min) |
| `com.user.sync-aw-to-calendar` | ActivityWatch → Calendar sync (30min) |
| `com.user.sync-ios-screentime-to-aw` | iOS Screen Time → ActivityWatch (1hr) |

**System daemons (/Library/LaunchDaemons/):**

| Label | Purpose |
|-------|---------|
| `com.github.jtroo-kanata` | Kanata keyboard remapper (sudo, needs Karabiner VirtualHIDDevice) |
| `net.mullvad.daemon` | Mullvad VPN daemon |
| `org.nixos.*` | Nix infrastructure (darwin-store, nix-daemon, activate-system) |
| `com.vmware.*` | VMware Fusion helpers |
| `com.docker.*` | Docker |
| `org.pqrs.*` | Karabiner-Elements VirtualHIDDevice |

## Important Notes

1. **No lint/typecheck commands** - Validation happens through `nix flake check` or building
2. **Colemak keyboard layout** - Window manager keybindings use Colemak (n/e/i/o = left/down/up/right)
3. **User "m"** - All configurations assume username "m"
4. **Shared folders** - VM mounts host filesystem at `/host` via VMware shared folders
5. **Firewall disabled** - Intentionally disabled in VMs for easier development access
6. **Determinate Nix on macOS** - Uses Determinate installer, so `nix.enable = false` in darwin config
7. **Home-manager integration** - Integrated as a NixOS/darwin module, not standalone; uses `useGlobalPkgs = true`
8. **Touch ID / Apple Watch sudo** - Configured via `security.pam.services.sudo_local` with `reattach = true` for tmux compatibility
9. **Fish shell enabled** - Fish is enabled on macOS alongside zsh (both have Nix daemon init)
10. **API keys injected per-process** - On Linux, secrets (GITHUB_TOKEN, OPENAI_API_KEY, etc.) are injected via rbw wrapper scripts and shell functions, NOT as global env vars
11. **No checked-in Makefile** - Use `docs/vm.sh`, `docs/macbook.sh`, and direct Nix commands instead
12. **New files must be git-added** - Nix flakes only see tracked files in dirty git trees
13. **nixpkgs 25.11 changes** - `darwin.apple_sdk_11_0` throws on access (use default `apple-sdk-14.4`); `du-dust` renamed to `dust`; `activitywatch` is Linux-only (use homebrew cask on Darwin)
14. **User prefers inline config** - Keep configuration inline in existing files rather than creating separate module files

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- bv-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View issues (launches TUI - avoid in automated sessions)
bv

# CLI commands for agents (use these instead)
br ready              # Show issues ready to work (no blockers)
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once
br sync               # Commit and push changes
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers, not words)
- **Types**: task, bug, feature, epic, question, docs
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync                 # Commit beads changes
git commit -m "..."     # Commit code
br sync                 # Commit any new beads changes
git push                # Push to remote
```

### Best Practices

- Check `br ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `br create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always `br sync` before ending session

<!-- end-bv-agent-instructions -->
