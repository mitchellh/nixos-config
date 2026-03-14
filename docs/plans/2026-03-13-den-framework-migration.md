# Den Framework Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the repo's handwritten `mkSystem` composition with a den-native host/user/aspect graph while preserving the existing target-specific behavior for `vm-aarch64`, `macbook-pro-m1`, and `wsl`.

**Architecture:** Create the final den structure first (`den/default.nix`, `den/hosts.nix`, `den/aspects/...`), then migrate behavior in vertical slices. Use a temporary `den/legacy.nix` bridge with `den.provides.import-tree` only long enough to keep the repo working while each slice moves to an explicit den aspect and gains a regression check.

**Tech Stack:** Nix flakes, den, import-tree, flake-aspects, nixpkgs, nix-darwin, NixOS, home-manager, sops-nix, sopsidy

---

## Execution Notes

- Perform implementation in the isolated worktree at `.worktrees/den-rewrite`.
- Any eval/build command that needs `machines/secrets.yaml` or private/generated files must run only in an authorized local checkout/worktree where those files are visible to Nix evaluation but remain untracked and uncommitted.
- Reuse the existing shell-test style already present in `tests/gpg-preset-passphrase.sh`; do not introduce a new test framework.
- Delete legacy files only after the den slice that replaces them is passing its regression check.

### Task 1: Bootstrap Den and the temporary legacy bridge

**Files:**
- Create: `den/default.nix`
- Create: `den/legacy.nix`
- Create: `tests/den/flake-smoke.sh`
- Modify: `flake.nix`
- Modify: `flake.lock`
- Test: `tests/den/flake-smoke.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'inputs.den.url = "github:vic/den";' flake.nix
grep -Fq 'inputs.den.flakeModule' den/default.nix
grep -Fq 'den.provides.import-tree' den/legacy.nix
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' flake.nix
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/flake-smoke.sh`
Expected: FAIL because `den/default.nix` and `den/legacy.nix` do not exist yet, and `flake.nix` does not reference den.

**Step 3: Write minimal implementation**

```nix
# den/default.nix
{ inputs, lib, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };
}
```

```nix
# den/legacy.nix
{ den, ... }: {
  den.ctx.host.includes = [ (den.provides.import-tree._.host ./../machines) ];
  den.ctx.user.includes = [ (den.provides.import-tree._.user ./../users) ];
}
```

```nix
# flake.nix (shape only)
let
  den = (inputs.nixpkgs.lib.evalModules {
    modules = [ (inputs.import-tree ./den) ];
    specialArgs.inputs = inputs;
  }).config;
in {
  inherit (den.flake) nixosConfigurations darwinConfigurations;
  # keep packages.*.collect-secrets manual
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/den/flake-smoke.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add flake.nix flake.lock den/default.nix den/legacy.nix tests/den/flake-smoke.sh
git commit -m "refactor: bootstrap den migration bridge"
```

### Task 2: Declare hosts and shared schema metadata

**Files:**
- Create: `den/hosts.nix`
- Create: `tests/den/host-schema.sh`
- Modify: `den/default.nix`
- Test: `tests/den/host-schema.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.users.m' den/hosts.nix
grep -Fq 'den.hosts.aarch64-darwin.macbook-pro-m1.users.m' den/hosts.nix
grep -Fq 'den.hosts.x86_64-linux.wsl.users.m' den/hosts.nix
grep -Fq 'options.profile' den/default.nix
grep -Fq 'options.vmware.enable' den/default.nix
grep -Fq 'options.wsl.enable' den/default.nix
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/host-schema.sh`
Expected: FAIL because `den/hosts.nix` and the custom schema options do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/default.nix
den.schema.host = { host, lib, types, ... }: {
  options.profile = lib.mkOption { type = types.str; };
  options.vmware.enable = lib.mkEnableOption "VMware-specific host behavior";
  options.wsl.enable = lib.mkEnableOption "WSL behavior";
  options.graphical.enable = lib.mkEnableOption "Graphical desktop behavior";
};
```

```nix
# den/hosts.nix
{
  den.hosts.aarch64-linux.vm-aarch64 = {
    profile = "vm";
    vmware.enable = true;
    graphical.enable = true;
    users.m = { };
  };

  den.hosts.aarch64-darwin.macbook-pro-m1 = {
    profile = "darwin-laptop";
    users.m = { };
  };

  den.hosts.x86_64-linux.wsl = {
    profile = "wsl";
    wsl.enable = true;
    users.m = { };
  };
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/den/host-schema.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/default.nix den/hosts.nix tests/den/host-schema.sh
git commit -m "refactor: declare den hosts and schema"
```

### Task 3: Move identity, hostname, and primary-user ownership into den aspects

**Files:**
- Create: `den/aspects/features/identity.nix`
- Create: `den/aspects/hosts/vm-aarch64.nix`
- Create: `den/aspects/hosts/macbook-pro-m1.nix`
- Create: `den/aspects/hosts/wsl.nix`
- Create: `den/aspects/users/m.nix`
- Create: `tests/den/identity.sh`
- Modify: `den/default.nix`
- Modify: `den/hosts.nix`
- Modify: `machines/vm-shared.nix`
- Modify: `users/m/nixos.nix`
- Modify: `users/m/darwin.nix`
- Test: `tests/den/identity.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  .#nixosConfigurations.vm-aarch64.config.networking.hostName | grep -Fx 'vm-macbook'

nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser | grep -Fx 'm'

nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  .#nixosConfigurations.wsl.config.wsl.defaultUser | grep -Fx 'm'

grep -Fq 'den.provides.define-user' den/aspects/features/identity.nix
grep -Fq 'den.provides.primary-user' den/aspects/features/identity.nix
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/identity.sh`
Expected: FAIL because the den identity aspect and host/user aggregators do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/identity.nix
{ den, ... }: {
  includes = [
    den.provides.define-user
    den.provides.primary-user
    den.provides.hostname
    (den.provides.user-shell "zsh")
  ];
}
```

```nix
# den/aspects/users/m.nix
{ den, ... }: {
  den.aspects.m.includes = [ den.aspects.identity ];
}
```

Remove duplicated ownership of `users.users.m`, `system.primaryUser`, and `networking.hostName` from the legacy modules once the aspect owns them.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/identity.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/identity.nix den/aspects/hosts/vm-aarch64.nix den/aspects/hosts/macbook-pro-m1.nix den/aspects/hosts/wsl.nix den/aspects/users/m.nix den/default.nix den/hosts.nix machines/vm-shared.nix users/m/nixos.nix users/m/darwin.nix tests/den/identity.sh
git commit -m "refactor: move identity wiring into den"
```

### Task 4: Extract the shared Home Manager shell and git slice

**Files:**
- Create: `den/aspects/features/shell-git.nix`
- Create: `tests/den/home-manager-core.sh`
- Modify: `den/aspects/users/m.nix`
- Modify: `users/m/home-manager.nix`
- Test: `tests/den/home-manager-core.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'shellAliases =' den/aspects/features/shell-git.nix
grep -Fq 'programs.git.enable = true;' den/aspects/features/shell-git.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.enable | grep -Fx 'true'

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.enable | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/home-manager-core.sh`
Expected: FAIL because `den/aspects/features/shell-git.nix` does not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/shell-git.nix
{
  homeManager = { pkgs, ... }: {
    programs.zsh.enable = true;
    programs.git.enable = true;
  };
}
```

Move the shared shell aliases, git identity, git signing defaults, and other shell/git-only content from `users/m/home-manager.nix` into this feature aspect.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/home-manager-core.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/shell-git.nix den/aspects/users/m.nix users/m/home-manager.nix tests/den/home-manager-core.sh
git commit -m "refactor: extract shell and git den aspect"
```

### Task 5: Extract GPG and signing behavior into a den aspect

**Files:**
- Create: `den/aspects/features/gpg.nix`
- Modify: `den/aspects/users/m.nix`
- Modify: `users/m/home-manager.nix`
- Modify: `tests/gpg-preset-passphrase.sh`
- Test: `tests/gpg-preset-passphrase.sh`

**Step 1: Write the failing test**

Update the existing test so it stops grepping `users/m/home-manager.nix` for GPG ownership and instead checks `den/aspects/features/gpg.nix`.

```bash
source_file=den/aspects/features/gpg.nix
grep -Fq 'vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";' "$source_file"
grep -Fq 'currentSystemName == "vm-aarch64"' "$source_file"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/gpg-preset-passphrase.sh`
Expected: FAIL because `den/aspects/features/gpg.nix` does not exist yet and the source assertions point at the new location.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/gpg.nix
{ host, ... }: {
  homeManager = {
    services.gpg-agent.enable = true;
    # move host-aware signing key and pinentry selection here
  };
}
```

Move the existing VM/Darwin signing key selection, pinentry behavior, helper script, and login preset-passphrase service into the den aspect. Keep the behavior unchanged; only move ownership.

**Step 4: Run test to verify it passes**

Run: `bash tests/gpg-preset-passphrase.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/gpg.nix den/aspects/users/m.nix users/m/home-manager.nix tests/gpg-preset-passphrase.sh
git commit -m "refactor: move gpg behavior into den"
```

### Task 6: Extract editors, developer tools, and AI tooling

**Files:**
- Create: `den/aspects/features/editors-devtools.nix`
- Create: `den/aspects/features/ai-tools.nix`
- Create: `tests/den/devtools.sh`
- Modify: `den/aspects/users/m.nix`
- Modify: `users/m/home-manager.nix`
- Test: `tests/den/devtools.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'pkgs.go' den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.nodejs_22' den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.llm-agents.copilot-cli' den/aspects/features/ai-tools.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.packages \
  --apply 'pkgs: builtins.any (pkg: (pkg.name or "") == "go") pkgs' | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/devtools.sh`
Expected: FAIL because the new den feature files do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/editors-devtools.nix
{
  homeManager = { pkgs, ... }: {
    home.packages = with pkgs; [ go nodejs_22 fnm ];
  };
}
```

```nix
# den/aspects/features/ai-tools.nix
{
  homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.llm-agents.copilot-cli ];
  };
}
```

Move the related package sets, editor integration, and AI tool configuration out of `users/m/home-manager.nix` into these aspects.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/devtools.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/editors-devtools.nix den/aspects/features/ai-tools.nix den/aspects/users/m.nix users/m/home-manager.nix tests/den/devtools.sh
git commit -m "refactor: extract devtools and ai den aspects"
```

### Task 7: Extract Linux core and secret-backed system behavior

**Files:**
- Create: `den/aspects/features/linux-core.nix`
- Create: `den/aspects/features/secrets.nix`
- Create: `tests/den/linux-core.sh`
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `users/m/nixos.nix`
- Modify: `machines/vm-shared.nix`
- Test: `tests/den/linux-core.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'services.tailscale.enable = true;' den/aspects/features/linux-core.nix
grep -Fq 'sops.defaultSopsFile = ./secrets.yaml;' den/aspects/features/secrets.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#nixosConfigurations.vm-aarch64.config.services.openssh.enable | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/linux-core.sh`
Expected: FAIL because the new Linux feature aspects do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/linux-core.nix
{
  nixos = {
    services.openssh.enable = true;
    services.tailscale.enable = true;
  };
}
```

```nix
# den/aspects/features/secrets.nix
{
  nixos = {
    sops.defaultSopsFile = ./secrets.yaml;
  };
}
```

Move Linux-only base services, Nix settings, `nix-ld`, mutable-user rules, and secret wiring out of the legacy modules. Run any secret-sensitive eval/build only in an authorized local worktree with the private files present but uncommitted.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/linux-core.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/linux-core.nix den/aspects/features/secrets.nix den/aspects/hosts/vm-aarch64.nix users/m/nixos.nix machines/vm-shared.nix tests/den/linux-core.sh
git commit -m "refactor: extract linux core den aspects"
```

### Task 8: Extract Linux desktop and VMware-specific behavior

**Files:**
- Create: `den/aspects/features/linux-desktop.nix`
- Create: `den/aspects/features/vmware.nix`
- Create: `tests/den/vm-desktop.sh`
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `machines/vm-aarch64.nix`
- Modify: `machines/vm-shared.nix`
- Modify: `users/m/home-manager.nix`
- Test: `tests/den/vm-desktop.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'programs.niri.enable = true;' den/aspects/features/linux-desktop.nix
grep -Fq 'virtualisation.vmware.guest.enable = true;' den/aspects/features/vmware.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#nixosConfigurations.vm-aarch64.config.programs.niri.enable | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/vm-desktop.sh`
Expected: FAIL because the desktop/VMware den aspects do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/linux-desktop.nix
{
  nixos.programs.niri.enable = true;
  nixos.services.noctalia-shell.enable = true;
}
```

```nix
# den/aspects/features/vmware.nix
{
  nixos.virtualisation.vmware.guest.enable = true;
}
```

Move the Wayland/Niri/Mango/Noctalia stack, HM Wayland settings, VMware mounts, and the Linux VM-specific file-system quirks into these aspects.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/vm-desktop.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/linux-desktop.nix den/aspects/features/vmware.nix den/aspects/hosts/vm-aarch64.nix machines/vm-aarch64.nix machines/vm-shared.nix users/m/home-manager.nix tests/den/vm-desktop.sh
git commit -m "refactor: extract vm desktop den aspects"
```

### Task 9: Extract Darwin core, Homebrew, and launchd behavior

**Files:**
- Create: `den/aspects/features/darwin-core.nix`
- Create: `den/aspects/features/homebrew.nix`
- Create: `den/aspects/features/launchd.nix`
- Create: `tests/den/darwin.sh`
- Modify: `den/aspects/hosts/macbook-pro-m1.nix`
- Modify: `users/m/darwin.nix`
- Modify: `machines/macbook-pro-m1.nix`
- Test: `tests/den/darwin.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'nix.enable = false;' den/aspects/features/darwin-core.nix
grep -Fq 'homebrew.enable = true;' den/aspects/features/homebrew.nix
grep -Fq 'launchd.user.agents.uniclip' den/aspects/features/launchd.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#darwinConfigurations.macbook-pro-m1.config.services.openssh.enable | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/darwin.sh`
Expected: FAIL because the Darwin den feature aspects do not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/darwin-core.nix
{
  darwin = {
    nix.enable = false;
    services.openssh.enable = true;
  };
}
```

```nix
# den/aspects/features/homebrew.nix
{
  darwin.homebrew.enable = true;
}
```

Move the Determinate-Nix settings, Darwin shell init, Touch ID sudo, Homebrew packages, MAS apps, and launchd agents into the den feature aspects while keeping their target-specific behavior unchanged.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/darwin.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/darwin-core.nix den/aspects/features/homebrew.nix den/aspects/features/launchd.nix den/aspects/hosts/macbook-pro-m1.nix users/m/darwin.nix machines/macbook-pro-m1.nix tests/den/darwin.sh
git commit -m "refactor: extract darwin den aspects"
```

### Task 10: Extract WSL-specific behavior

**Files:**
- Create: `den/aspects/features/wsl.nix`
- Create: `tests/den/wsl.sh`
- Modify: `den/aspects/hosts/wsl.nix`
- Modify: `machines/wsl.nix`
- Test: `tests/den/wsl.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -Fq 'wsl.enable = true;' den/aspects/features/wsl.nix

nix --extra-experimental-features 'nix-command flakes' eval --impure --json \
  .#nixosConfigurations.wsl.config.wsl.enable | grep -Fx 'true'
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/wsl.sh`
Expected: FAIL because the WSL aspect does not exist yet.

**Step 3: Write minimal implementation**

```nix
# den/aspects/features/wsl.nix
{
  nixos.wsl.enable = true;
}
```

Move the WSL module wiring, automount behavior, and unstable Nix package selection into the den WSL aspect and the host aggregator.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/wsl.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add den/aspects/features/wsl.nix den/aspects/hosts/wsl.nix machines/wsl.nix tests/den/wsl.sh
git commit -m "refactor: extract wsl den aspect"
```

### Task 11: Remove the legacy bridge, delete handwritten composition, and update docs

**Files:**
- Create: `tests/den/no-legacy.sh`
- Modify: `flake.nix`
- Modify: `README.md`
- Modify: `docs/secrets.md`
- Delete: `den/legacy.nix`
- Delete: `lib/mksystem.nix`
- Delete: `machines/vm-aarch64.nix`
- Delete: `machines/vm-shared.nix`
- Delete: `machines/macbook-pro-m1.nix`
- Delete: `machines/wsl.nix`
- Delete: `users/m/home-manager.nix`
- Delete: `users/m/nixos.nix`
- Delete: `users/m/darwin.nix`
- Test: `tests/den/no-legacy.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

test ! -e den/legacy.nix
test ! -e lib/mksystem.nix
test ! -e users/m/home-manager.nix
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' flake.nix
grep -Fq 'den/' README.md
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/no-legacy.sh`
Expected: FAIL because the bridge and legacy files still exist.

**Step 3: Write minimal implementation**

Remove the legacy bridge and the old handwritten composition files only after all previous tasks pass. Update the human docs so the new den-centric layout is discoverable.

```nix
# flake.nix
{
  outputs = inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [ (inputs.import-tree ./den) ];
      specialArgs.inputs = inputs;
    }).config.flake;
}
```

If the repo still needs manual `packages.*.collect-secrets`, keep them in `flake.nix` next to the inherited den outputs instead of reintroducing handwritten host composition.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/no-legacy.sh && bash tests/den/flake-smoke.sh && bash tests/den/host-schema.sh && bash tests/den/identity.sh && bash tests/den/home-manager-core.sh && bash tests/den/devtools.sh && bash tests/den/linux-core.sh && bash tests/den/vm-desktop.sh && bash tests/den/darwin.sh && bash tests/den/wsl.sh && bash tests/gpg-preset-passphrase.sh`
Expected: PASS

Run in an authorized local checkout/worktree with private files visible to Nix evaluation:

```bash
nix --extra-experimental-features 'nix-command flakes' eval --impure --raw .#nixosConfigurations.vm-aarch64.config.networking.hostName
nix --extra-experimental-features 'nix-command flakes' eval --impure --raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser
nix --extra-experimental-features 'nix-command flakes' eval --impure --json .#nixosConfigurations.wsl.config.wsl.enable
```

Expected: all commands succeed with the existing host-specific values.

**Step 5: Commit**

```bash
git add flake.nix README.md docs/secrets.md tests/den/no-legacy.sh
git rm den/legacy.nix lib/mksystem.nix machines/vm-aarch64.nix machines/vm-shared.nix machines/macbook-pro-m1.nix machines/wsl.nix users/m/home-manager.nix users/m/nixos.nix users/m/darwin.nix
git commit -m "refactor: complete den migration"
```
