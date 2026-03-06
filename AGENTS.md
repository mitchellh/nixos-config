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

The `lib/mksystem.nix` function is the core abstraction that enables multi-platform support. It takes a machine name and configuration options, then assembles the appropriate modules based on the target platform.

```
flake.nix
  │
  ├── mkSystem "vm-aarch64" { system = "aarch64-linux"; }     → NixOS VM (ARM)
  ├── mkSystem "wsl" { system = "x86_64-linux"; wsl = true; } → WSL
  └── mkSystem "macbook-pro-m1" { darwin = true; }            → macOS
```

### Platform Detection Mechanism

In `lib/mksystem.nix`, platform flags determine which modules and configurations to apply:

```nix
# Boolean flags derived from mkSystem arguments
isWSL = wsl;                    # WSL-specific behavior
isLinux = !darwin && !isWSL;    # Full Linux (VM with GUI)
darwin = darwin;                # macOS via nix-darwin

# Platform-specific function selection
systemFunc = if darwin
  then inputs.darwin.lib.darwinSystem
  else nixpkgs.lib.nixosSystem;
```

These flags are passed to modules via `config._module.args` and to home-manager, enabling conditional configuration throughout the codebase.

### Conditional Configuration Patterns

**In `home-manager.nix`** - use `pkgs.stdenv` for package-level conditionals:
```nix
isDarwin = pkgs.stdenv.isDarwin;
isLinux = pkgs.stdenv.isLinux;

home.packages = [
  pkgs.common-package
] ++ (lib.optionals isDarwin [ pkgs.mac-only ])
  ++ (lib.optionals (isLinux && !isWSL) [ pkgs.gui-linux-only ]);
```

**In machine configs** - use `currentSystemName` for machine-specific overrides:
```nix
environment.systemPackages = lib.optionals (currentSystemName == "vm-aarch64") [
  pkgs.vmware-specific-package
];
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

The macOS host and NixOS VM share a clipboard via uniclip over an SSH reverse tunnel:

```
macOS (host)                              VM (guest)
┌──────────────────────┐                 ┌──────────────────────┐
│ uniclip server       │                 │ uniclip client       │
│ --secure             │                 │ --secure             │
│ --bind 127.0.0.1     │                 │ 127.0.0.1:53701      │
│ -p 53701             │                 │                      │
│ UNICLIP_PASSWORD=... │                 │ UNICLIP_PASSWORD=... │
│ (from rbw)           │                 │ (from rbw)           │
│                      │                 │                      │
│ SSH -R tunnel ──────────── SSH ──────> │ sshd                 │
│ 53701→127.0.0.1:53701│                 │ remote fwd :53701    │
└──────────────────────┘                 └──────────────────────┘
```

**Key details:**
- Uniclip is built from source with a custom patch (`patches/uniclip-bind-and-env-password.patch`) that adds `--bind` flag and `UNICLIP_PASSWORD` env var support
- Password stored in rbw (Bitwarden) as `uniclip-password`
- macOS side: two launchd agents in `users/m/darwin.nix` — `uniclip` (server) and `uniclip-tunnel` (SSH reverse tunnel using `vmrun` to find VM IP)
- VM side: systemd user service in `users/m/home-manager.nix` — `uniclip` (client connecting to `127.0.0.1:53701`)
- Full documentation in `docs/clipboard-sharing.md`

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `/lib/` | Core library functions - contains `mksystem.nix` which is the main system builder |
| `/machines/` | Machine-specific configurations (VM, MacBook, WSL) |
| `/machines/hardware/` | Hardware-specific configurations (auto-generated by `nixos-generate-config`) |
| `/machines/generated/` | Generated files (SSH pubkeys, age keys for sops) |
| `/modules/` | Reusable NixOS modules |
| `/modules/specialization/` | System specializations (alternative desktop environments, e.g., GNOME+ibus) |
| `/users/` | Per-user home-manager and OS-specific configurations |
| `/users/m/` | User "m" configurations (home-manager, dotfiles, shell configs) |
| `/users/m/doom/` | Doom Emacs configuration (init.el, packages.el, config.org, custom.el, themes/) |
| `/users/m/lazyvim/` | LazyVim Neovim configuration |
| `/patches/` | Source patches (uniclip bind+env password patch) |
| `/docs/` | Documentation and helper scripts |
| `/scripts/` | VM creation and provisioning scripts |
| `/.github/` | GitHub workflows (GitHub Pages deployment) |

### User Configuration Files (in `/users/m/`)

| File | Purpose |
|------|---------|
| `home-manager.nix` | Main home-manager config - packages, programs, dotfiles (shared across platforms) |
| `nixos.nix` | NixOS-specific user settings (user account, groups, shell) - used by VM and WSL |
| `darwin.nix` | macOS-specific settings (Homebrew apps, launchd agents, user shell) |
| `ghostty.linux` | Ghostty terminal configuration for Linux |
| `bashrc`, `inputrc`, `gdbinit` | Shell and tool configurations |

## Build Commands (Makefile)

**Important:** The Makefile defaults `NIXNAME` to `vm-aarch64`. You MUST pass `NIXNAME=macbook-pro-m1` for Darwin builds.

The Makefile exports VMware Fusion CLI tools on PATH:
```makefile
export PATH := /Applications/VMware Fusion.app/Contents/Library:$(PATH)
```

| Command | Description |
|---------|-------------|
| `make switch` | Apply the NixOS/nix-darwin configuration to the current system |
| `make test` | Test the configuration without applying it permanently |
| `make vm/create` | Create a new VM (runs `scripts/vm-create.sh`) |
| `make vm/install` | Full VM install: prepare keys, collect secrets, rsync, disko partition, nixos-install, reboot |
| `make vm/copy` | Copy Nix configurations to a running VM (two-step rsync) |
| `make vm/switch` | Run `nixos-rebuild switch` on the remote VM |
| `make vm/update` | Auto-detect VM IP via `vmrun`, then copy + switch |
| `make vm/age-key` | Fetch or create sops age key on VM |
| `make vm/prepare-sops-host-pubkey` | Bootstrap sops age key using `sshpass` (password auth) |
| `make vm/prepare-host-authorized-keys` | Copy host SSH pubkey to `machines/generated/` |
| `make secrets/collect` | Sopsidy secret collection (stages secrets.yaml for flake eval) |
| `make wsl` | Build a WSL root tarball installer |

**Environment Variables for VM Operations:**
- `NIXADDR` - IP address of the target VM (default: `unset`, auto-detected by `vm/update`)
- `NIXPORT` - SSH port (default: 22)
- `NIXUSER` - Username (default: m)
- `NIXNAME` - Configuration name (default: vm-aarch64)
- `NIXBLOCKDEVICE` - Block device for disko partitioning (default: nvme0n1)

## Key Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Main entry point - defines all system configurations and inputs |
| `flake.lock` | Locked versions of all flake inputs (dependencies) |
| `Makefile` | Build automation and VM management commands |
| `lib/mksystem.nix` | System builder function - creates NixOS/darwin configurations |
| `machines/vm-shared.nix` | Shared VM configuration (Wayland, Niri, Docker, etc.) |
| `machines/vm-aarch64.nix` | ARM64 VM configuration (VMware Fusion) |
| `machines/macbook-pro-m1.nix` | macOS configuration via nix-darwin (Touch ID sudo, shells, linux-builder) |
| `machines/wsl.nix` | WSL-specific configuration |
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

## Module Orchestration (lib/mksystem.nix)

The `mksystem.nix` function composes modules in this order:

1. **Overlays** applied globally (`nixpkgs.overlays = overlays; nixpkgs.config.allowUnfree = true`)
2. **Platform-specific NixOS modules** (all `isLinux`-gated):
   - WSL, Snapd, Niri, Disko, Mango, Noctalia, Sops-nix, Sopsidy
3. **Machine config** (`machines/${name}.nix`)
4. **OS-specific user config** (`users/${user}/darwin.nix` or `users/${user}/nixos.nix`)
5. **Home-Manager** integration:
   - `useGlobalPkgs = true`, `useUserPackages = true`
   - `backupFileExtension = "backup"` (prevents clobbering existing dotfiles)
   - **Shared modules** (always): lazyvim, nix-doom-emacs-unstraightened, mangowc, noctalia
   - **Shared modules** (Darwin-only): niri homeModules (needed because on Linux, the NixOS module already registers the HM module — loading it again causes double-declaration)
   - User config: `import userHMConfig { isWSL; inputs; }`
6. **Extra module args**: `currentSystem`, `currentSystemName`, `currentSystemUser`, `isWSL`, `inputs`

### Important Module System Lessons

- **HM modules must be declared unconditionally**: `programs.niri`, `wayland.windowManager.mango`, `programs.noctalia-shell` — using `lib.mkIf` only guards values, not option declarations. If the module isn't loaded, the option doesn't exist.
- **Niri double-declaration**: Loading `inputs.niri.homeModules.niri` unconditionally in `sharedModules` causes errors on Linux because `inputs.niri.nixosModules.niri` already registers the HM module. Fix: only add it to `sharedModules` on Darwin.
- **`lib.optionalAttrs` with `pkgs.stdenv.isDarwin`** causes infinite recursion in module system — don't use it for conditional module structure.
- **`home-manager.backupFileExtension`** must be set or first switch fails when existing dotfiles would be clobbered.

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

### Module Arguments

These are available in machine and user configs via `config._module.args`:
- `currentSystem` - e.g., `"aarch64-linux"`, `"aarch64-darwin"`
- `currentSystemName` - e.g., `"vm-aarch64"`, `"macbook-pro-m1"`
- `currentSystemUser` - e.g., `"m"`
- `isWSL` - boolean
- `inputs` - all flake inputs

## macOS Configuration (machines/macbook-pro-m1.nix)

- `system.stateVersion = 5` (macOS Sequoia)
- `nix.enable = false` (Determinate Nix installer manages Nix)
- `nix.settings.trusted-users = ["@admin"]`
- **Touch ID sudo**: `security.pam.services.sudo_local` with `touchIdAuth = true`, `watchIdAuth = true`, `reattach = true`
- **Shells**: zsh and fish enabled, both with Nix daemon init
- **Linux builder**: Defined but disabled (`enable = false`). Config: 6 cores, 100GB disk, 32GB RAM
- `environment.systemPackages = [ cachix ]`

## macOS Homebrew Apps (users/m/darwin.nix)

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
# Evaluate a specific configuration without building
nix eval .#nixosConfigurations.vm-aarch64.config.networking.hostName

# Open a REPL with the flake loaded
nix repl .#nixosConfigurations.vm-aarch64

# Check flake for errors
nix flake check

# Show what would be built/changed
nixos-rebuild dry-run --flake .#vm-aarch64

# Build without switching (outputs to ./result)
nixos-rebuild build --flake .#vm-aarch64

# Show derivation details
nix derivation show .#nixosConfigurations.vm-aarch64.config.system.build.toplevel

# List available outputs
nix flake show
```

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `error: attribute 'X' missing` | Typo in option name or missing import | Check spelling; verify the module providing the option is imported |
| `infinite recursion encountered` | Circular dependency in config | Avoid referencing `config` in the same expression that defines it; use `lib.mkIf`. Do NOT use `lib.optionalAttrs` with `pkgs.stdenv.isDarwin` for module structure. |
| `collision between X and Y` | Two packages provide the same file | Use `lib.hiPrio` or remove one package |
| `hash mismatch in fixed-output derivation` | Upstream source changed | Run `nix flake update` or update the hash |
| `experimental feature 'flakes' is disabled` | Nix not configured for flakes | Ensure `experimental-features = nix-command flakes` is set |
| `Existing file would be clobbered` | home-manager dotfile conflict | Set `home-manager.backupFileExtension = "backup"` in mksystem.nix |
| HM option `programs.X` not found | Module not loaded in sharedModules | Add the HM module to sharedModules in mksystem.nix; use `lib.mkIf` to conditionally set values |
| Niri double-declaration on Linux | niri NixOS module already registers HM module | Only add `niri.homeModules.niri` to sharedModules on Darwin |

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

# Must pass NIXNAME for Darwin
NIXNAME=macbook-pro-m1 make switch
```

**Makefile subshell PATH issues:**
- `home.sessionPath` only affects login shells, NOT Make subshells
- VMware Fusion PATH must be set in the Makefile itself (done via `export PATH := ...`)

## Common Tasks for AI Agents

### Adding a New Package

1. **Determine scope:**
   - System-wide (all users): `machines/vm-shared.nix` → `environment.systemPackages`
   - User-only: `users/m/home-manager.nix` → `home.packages`

2. **Consider platform:**
   ```nix
   home.packages = [
     pkgs.cross-platform
   ] ++ (lib.optionals isDarwin [ pkgs.mac-only ])
     ++ (lib.optionals (isLinux && !isWSL) [ pkgs.gui-linux-only ]);
   ```

3. **macOS GUI apps**: Add to `users/m/darwin.nix` → `homebrew.casks` (or `masApps` for App Store)

4. **Test:** `make test` or `nix build .#nixosConfigurations.<name>.config.system.build.toplevel`

5. **Remember:** New files must be `git add`ed before building — Nix flakes only see tracked files in dirty git trees.

### Modifying Shell Configuration

- **Aliases:** Edit `shellAliases` in `users/m/home-manager.nix`
- **Zsh settings:** Edit `programs.zsh` in same file
- **Zsh init:** Edit `programs.zsh.initContent` (platform-conditional blocks for brew shellenv, rbw wrappers, etc.)
- **Bash settings:** Edit `programs.bash` or `users/m/bashrc`

### Adding a New Machine

1. Create `machines/<name>.nix`
2. If needed, create `machines/hardware/<name>.nix` (auto-generated by `nixos-generate-config`)
3. Add entry in `flake.nix`:
   ```nix
   nixosConfigurations.<name> = mkSystem "<name>" {
     system = "x86_64-linux";  # or aarch64-linux, aarch64-darwin
     user = "m";
     # wsl = true;   # for WSL
     # darwin = true; # for macOS
   };
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
sudo nixos-rebuild switch --flake .#vm-aarch64 --specialisation gnome-ibus
```

### Secrets Management

- **rbw (Bitwarden):** Used for runtime secrets on Linux (API keys, tokens, passwords)
- **sops-nix + sopsidy:** Used for declarative secrets in NixOS configurations
- API keys are injected per-process via shell functions and wrapper scripts, NOT as global env vars
- `make secrets/collect` collects sopsidy secrets; `make vm/age-key` manages VM age keys

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

## Doom Emacs Configuration (users/m/doom/)

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

**Nix-managed (users/m/darwin.nix):**

| Label | Purpose |
|-------|---------|
| `org.nixos.uniclip` | Uniclip server (encrypted clipboard sharing, `127.0.0.1:53701`) |
| `org.nixos.uniclip-tunnel` | SSH reverse tunnel to forward clipboard port into VM |

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
11. **Makefile NIXNAME default** - Defaults to `vm-aarch64`. Must pass `NIXNAME=macbook-pro-m1` for Darwin builds
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
