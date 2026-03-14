# Den Native Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the den rewrite so it follows den's own structure more closely, removes migration-era scaffolding, and handles WSL/VM behavior through den-native composition instead of repo-local special casing.

**Architecture:** Keep `den/default.nix` limited to true global policy, schema, and integration hooks; let host aspects select features and own one-off behavior; keep WSL expressed the way den already supports it via `host.wsl.enable`; and push WSL/VM-specific deltas out of broad reusable features and into host-owned config. The refactor should preserve current behavior for `vm-aarch64`, `macbook-pro-m1`, and `wsl` while making the graph easier to read and less stateful.

**Tech Stack:** Nix flakes, den, nixos-wsl, home-manager, nix-darwin, sops-nix, sopsidy, shell-based regression tests

---

## Execution Notes

- Work inside the current repo checkout unless a separate worktree is created before implementation.
- Do not add a new test framework; extend the existing shell tests under `tests/den/` and `tests/gpg-preset-passphrase.sh`.
- Keep behavior stable while removing structural overengineering.
- Prefer deleting dead indirection over replacing it with new schema flags.

### Task 1: Make den defaults and host declarations den-native

**Files:**
- Modify: `tests/den/host-schema.sh`
- Modify: `den/default.nix`
- Modify: `den/hosts.nix`
- Modify: `docs/plans/2026-03-14-den-native-redesign.md`

**Step 1: Write the failing test**

Update `tests/den/host-schema.sh` so it enforces the corrected scope:

```bash
if grep -Fq 'den._.wsl' den/default.nix; then
  echo "ERROR: den/default.nix must not include den._.wsl" >&2
  exit 1
fi
grep -Fq 'den.ctx.hm-host.includes' den/default.nix

if grep -Fq 'options.profile' den/default.nix; then
  echo "ERROR: profile should be removed from den/default.nix" >&2
  exit 1
fi
grep -Fq 'options.vmware.enable' den/default.nix
grep -Fq 'options.graphical.enable' den/default.nix

grep -Fq 'den.hosts.x86_64-linux.wsl.wsl.enable = true' den/hosts.nix
grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.vmware.enable = true' den/hosts.nix
grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.graphical.enable = true' den/hosts.nix
if rg -n 'profile = ' den/hosts.nix >/dev/null; then
  echo "ERROR: den/hosts.nix should drop only profile host assignments in Task 1" >&2
  exit 1
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/host-schema.sh`

Expected: FAIL because Task 1 must keep `vmware.enable` and `graphical.enable` in both schema and host assignments until Tasks 3-6 migrate their remaining consumers.

**Step 3: Write minimal implementation**

Refactor `den/default.nix` and `den/hosts.nix` only as far as this task needs:

```nix
# den/default.nix
den.default = {
  nixos = {
    nixpkgs.overlays = overlays;
    nixpkgs.config.allowUnfree = true;
  };

  darwin = {
    nixpkgs.overlays = overlays;
    nixpkgs.config.allowUnfree = true;
  };
};

den.schema.host = { lib, ... }: {
  options.vmware.enable = lib.mkEnableOption "VMware-specific host behavior";
  options.graphical.enable = lib.mkEnableOption "Graphical desktop behavior";
};
```

```nix
# den/hosts.nix
{
  den.hosts.aarch64-linux.vm-aarch64.hostName = "vm-macbook";
  den.hosts.aarch64-linux.vm-aarch64.vmware.enable = true;
  den.hosts.aarch64-linux.vm-aarch64.graphical.enable = true;
  den.hosts.aarch64-linux.vm-aarch64.users.m = { };

  den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };

  den.hosts.x86_64-linux.wsl.wsl.enable = true;
  den.hosts.x86_64-linux.wsl.users.m = { };
}
```

Remove only the `profile` schema and host assignments in Task 1. Keep `den.ctx.hm-host.includes` intact. Do not remove `vmware.enable` or `graphical.enable` until Tasks 3-6 have migrated `vmware.nix`, `linux-desktop.nix`, `gpg.nix`, and `shell-git.nix` away from those fields.

**Step 4: Run tests to verify it passes**

Run: `bash tests/den/host-schema.sh && bash tests/den/vm-desktop.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/host-schema.sh den/default.nix den/hosts.nix docs/plans/2026-03-14-den-native-redesign.md
git -c commit.gpgsign=false commit -m "fix: restore den host flags for pending migrations" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 2: Keep WSL activation on den's existing host wiring and the WSL host aspect

**Files:**
- Modify: `tests/den/wsl.sh`
- Modify: `tests/den/no-legacy.sh`
- Modify: `den/aspects/hosts/wsl.nix`
- Delete: `den/aspects/features/wsl.nix`

**Step 1: Write the failing test**

Update `tests/den/wsl.sh` so it stops expecting repo-local NixOS-WSL wiring and instead enforces den-native ownership:

```bash
if grep -Fq 'den._.wsl' den/default.nix; then
  echo "FAIL: den/default.nix should not include den._.wsl" >&2
  exit 1
fi
test -f den/aspects/hosts/wsl.nix
if [ -e den/aspects/features/wsl.nix ]; then
  echo "FAIL: den/aspects/features/wsl.nix should be removed" >&2
  exit 1
fi

grep -Fq 'wsl.wslConf.automount.root = "/mnt";' den/aspects/hosts/wsl.nix
grep -Fq 'wsl.startMenuLaunchers = true;' den/aspects/hosts/wsl.nix
grep -Fq 'nix.package = pkgs.nixVersions.latest;' den/aspects/hosts/wsl.nix
grep -Fq 'system.stateVersion = "23.05";' den/aspects/hosts/wsl.nix
```

Change the provenance checks so:

- `wsl.enable` comes from `provides/wsl.nix`
- `wsl.defaultUser` comes from `provides/wsl.nix`
- `wsl.wslConf.automount.root` comes from `den/aspects/hosts/wsl.nix`

Also update `tests/den/no-legacy.sh` to fail if `inputs.nixos-wsl.nixosModules.wsl` still appears under `den/aspects/features/`.

**Step 2: Run test to verify it fails**

Run: `bash tests/den/wsl.sh && bash tests/den/no-legacy.sh`

Expected: FAIL because WSL activation still lives in `den/aspects/features/wsl.nix`.

**Step 3: Write minimal implementation**

Delete the repo-local WSL activation aspect and move only repo-specific WSL settings into the host aspect:

```nix
# den/aspects/hosts/wsl.nix
{ den, ... }: {
  den.aspects.wsl = {
    nixos = { pkgs, ... }: {
      wsl.wslConf.automount.root = "/mnt";
      wsl.startMenuLaunchers = true;

      nix.package = pkgs.nixVersions.latest;
      nix.extraOptions = ''
        keep-outputs = true
        keep-derivations = true
      '';
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      system.stateVersion = "23.05";
    };
  };
}
```

Do not reintroduce `options.wsl.enable`, a custom `den.provides.wsl`, or `den._.wsl` here; keep relying on den's built-in host wiring via `den.hosts.x86_64-linux.wsl.wsl.enable = true`.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/wsl.sh && bash tests/den/no-legacy.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/wsl.sh tests/den/no-legacy.sh den/aspects/hosts/wsl.nix
git rm den/aspects/features/wsl.nix
git -c commit.gpgsign=false commit -m "refactor: route wsl through den battery" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 3: Move vm-aarch64-only VM behavior out of the generic VMware feature

**Files:**
- Modify: `tests/den/vm-desktop.sh`
- Modify: `den/aspects/features/vmware.nix`
- Modify: `den/aspects/hosts/vm-aarch64.nix`

**Step 1: Write the failing test**

Update `tests/den/vm-desktop.sh` so it enforces the new ownership split:

```bash
grep -Fq 'virtualisation.vmware.guest.enable' den/aspects/features/vmware.nix
grep -Fq 'environment.systemPackages = [ pkgs.gtkmm3 ];' den/aspects/features/vmware.nix

if grep -Eq 'programs\.ssh|programs\.niri\.settings|DOCKER_CONTEXT|yeetAndYoink|mac-host-docker|ensureHostDockerContext|uniclip|\.host:/Projects|\.host:/nixos-config|\.host:/nixos-generated' den/aspects/features/vmware.nix; then
  echo "FAIL: den/aspects/features/vmware.nix still owns vm-aarch64-specific behavior" >&2
  exit 1
fi

grep -Fq '.host:/Projects' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'programs.ssh' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'programs.niri.settings' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'DOCKER_CONTEXT' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'ensureHostDockerContext' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'systemd.user.services.uniclip' den/aspects/hosts/vm-aarch64.nix
```

Also make the test fail if `den/aspects/features/vmware.nix` still checks `host.vmware.enable`.

**Step 2: Run test to verify it fails**

Run: `bash tests/den/vm-desktop.sh`

Expected: FAIL because `den/aspects/features/vmware.nix` still owns HGFS mounts, Niri config, Docker context, SSH, and other vm-aarch64-only details.

**Step 3: Write minimal implementation**

Reduce `den/aspects/features/vmware.nix` to reusable VMware guest integration:

```nix
# den/aspects/features/vmware.nix
{ den, ... }: {
  den.aspects.vmware = {
    nixos = { pkgs, ... }: {
      virtualisation.vmware.guest.enable = true;
      environment.systemPackages = [ pkgs.gtkmm3 ];
    };
  };
}
```

Move the following into `den/aspects/hosts/vm-aarch64.nix`:

- HGFS mounts
- `nixpkgs.config.allowUnsupportedSystem = true`
- `/Users/m/Projects` first-switch fallback logic
- yeet-and-yoink plugin build
- `DOCKER_CONTEXT`
- `programs.ssh.matchBlocks."mac-host-docker"`
- `programs.niri.settings`
- `programs.zellij.settings.load_plugins`
- `home.activation.ensureHostDockerContext`
- `systemd.user.services.uniclip`
- VM-only `home.packages` additions like `pkgs.docker-client`

Keep `den.aspects.vmware` in the host aspect include chain, but let the host aspect own everything that is only true for `vm-aarch64`.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/vm-desktop.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/vm-desktop.sh den/aspects/features/vmware.nix den/aspects/hosts/vm-aarch64.nix
git -c commit.gpgsign=false commit -m "refactor: move vm host logic out of vmware feature" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 4: Make the Linux desktop aspect host-selected instead of self-gated

**Files:**
- Modify: `tests/den/vm-desktop.sh`
- Modify: `den/aspects/features/linux-desktop.nix`

**Step 1: Write the failing test**

Extend `tests/den/vm-desktop.sh` with static checks that reject host-flag gating inside the feature:

```bash
if grep -Fq 'host.graphical.enable' den/aspects/features/linux-desktop.nix; then
  echo "FAIL: linux-desktop should be selected by host composition, not host.graphical.enable" >&2
  exit 1
fi
if grep -Fq 'isGraphical =' den/aspects/features/linux-desktop.nix; then
  echo "FAIL: linux-desktop still computes isGraphical" >&2
  exit 1
fi
if grep -Fq 'lib.mkIf isGraphical' den/aspects/features/linux-desktop.nix; then
  echo "FAIL: linux-desktop still self-gates with lib.mkIf isGraphical" >&2
  exit 1
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/vm-desktop.sh`

Expected: FAIL because `linux-desktop.nix` still gates itself with `host.graphical.enable` and `lib.mkIf isGraphical`.

**Step 3: Write minimal implementation**

Turn `den/aspects/features/linux-desktop.nix` into a direct feature module:

```nix
den.aspects.linux-desktop = {
  nixos = { config, pkgs, ... }: {
    imports = [
      inputs.niri.nixosModules.niri
      inputs.mangowc.nixosModules.mango
      inputs.noctalia.nixosModules.default
    ];

    programs.niri.enable = true;
    services.noctalia-shell.enable = true;
    services.greetd.enable = true;
    # ...
  };

  homeManager = { pkgs, ... }: {
    imports = [
      inputs.noctalia.homeModules.default
      inputs.mangowc.hmModules.mango
    ];

    home.packages = [
      pkgs.brave
      pkgs.ghostty
      # ...
    ];
    programs.kitty.enable = true;
    programs.wayprompt.enable = true;
    # ...
  };
};
```

Because only `den/aspects/hosts/vm-aarch64.nix` includes this feature, the host aspect becomes the condition.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/vm-desktop.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/vm-desktop.sh den/aspects/features/linux-desktop.nix
git -c commit.gpgsign=false commit -m "refactor: make linux-desktop host-selected" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 5: Push remaining VM/WSL user deltas into host-owned config

**Files:**
- Modify: `tests/den/home-manager-core.sh`
- Modify: `tests/den/devtools.sh`
- Modify: `den/aspects/features/home-base.nix`
- Modify: `den/aspects/features/shell-git.nix`
- Modify: `den/aspects/features/ai-tools.nix`
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `den/aspects/hosts/wsl.nix`
- Delete: `dotfiles/common/opencode/modules/home-manager.nix`

**Step 1: Write the failing test**

Update the static checks so these files fail if they still carry WSL/VM plumbing:

```bash
if rg -n 'isWSL|isVM|host\.wsl\.enable|host\.vmware\.enable' \
  den/aspects/features/home-base.nix \
  den/aspects/features/shell-git.nix \
  den/aspects/features/ai-tools.nix >/dev/null; then
  echo "FAIL: common Home Manager features still contain WSL/VM special casing" >&2
  exit 1
fi

if [ -e dotfiles/common/opencode/modules/home-manager.nix ]; then
  echo "FAIL: parameterized opencode HM bridge should be removed" >&2
  exit 1
fi

grep -Fq 'GENERATED_INPUT_DIR' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'YEET_AND_YOINK_INPUT_DIR' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'opencode-serve' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'opencode-web' den/aspects/hosts/vm-aarch64.nix
grep -Fq 'pinentry-tty' den/aspects/hosts/wsl.nix
```

Also add live eval checks:

- `vm-aarch64` still has `opencode-serve` / `opencode-web`
- `wsl` does not
- `vm-aarch64` still resolves `programs.rbw.settings.pinentry` to `pinentry-wayprompt`
- `wsl` resolves it to `pinentry-tty`

**Step 2: Run test to verify it fails**

Run: `bash tests/den/home-manager-core.sh && bash tests/den/devtools.sh`

Expected: FAIL because `home-base.nix`, `shell-git.nix`, and `ai-tools.nix` still use `isWSL` / `isVM`, and the parameterized OpenCode module still exists.

**Step 3: Write minimal implementation**

Refactor the user features so they are generic, and let host aspects add the deltas:

```nix
# den/aspects/features/home-base.nix
programs.rbw = {
  enable = true;
  settings = {
    base_url = "https://api.bitwarden.eu";
    email = "overwritten-by-systemd";
    lock_timeout = 86400;
  };
};
```

```nix
# den/aspects/features/shell-git.nix
generatedDirSetup = ''
  generated_dir="''${GENERATED_INPUT_DIR-$HOME/.local/share/nix-config-generated}"
'';
yeetAndYoinkDirSetup = ''
  yeet_and_yoink_dir="''${YEET_AND_YOINK_INPUT_DIR-$HOME/Projects/yeet-and-yoink}"
'';
```

```nix
# den/aspects/features/ai-tools.nix
programs.zsh.shellAliases.opencode-dev = "${pkgs.opencode-dev}/bin/opencode";
programs.bash.shellAliases.opencode-dev = "${pkgs.opencode-dev}/bin/opencode";
```

Then move these into host aspects:

- `vm-aarch64`: `GENERATED_INPUT_DIR`, `YEET_AND_YOINK_INPUT_DIR`, `git-credential-github`, `opencode-serve`, `opencode-web`, `pinentry-wayprompt`
- `wsl`: `pinentry-tty`

Delete `dotfiles/common/opencode/modules/home-manager.nix` once `ai-tools.nix` no longer imports it.

**Step 4: Run test to verify it passes**

Run: `bash tests/den/home-manager-core.sh && bash tests/den/devtools.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/home-manager-core.sh tests/den/devtools.sh \
  den/aspects/features/home-base.nix den/aspects/features/shell-git.nix den/aspects/features/ai-tools.nix \
  den/aspects/hosts/vm-aarch64.nix den/aspects/hosts/wsl.nix
git rm dotfiles/common/opencode/modules/home-manager.nix
git -c commit.gpgsign=false commit -m "refactor: move host-specific hm deltas to host aspects" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 6: Move GPG and secret-host differences into host aspects

**Files:**
- Modify: `tests/gpg-preset-passphrase.sh`
- Modify: `tests/den/wsl.sh`
- Modify: `den/aspects/features/gpg.nix`
- Modify: `den/aspects/features/secrets.nix`
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `den/aspects/hosts/macbook-pro-m1.nix`
- Modify: `den/aspects/hosts/wsl.nix`

**Step 1: Write the failing test**

Update `tests/gpg-preset-passphrase.sh` so it reflects the new ownership split:

```bash
if grep -Fq 'isVM' den/aspects/features/gpg.nix; then
  fail 'gpg.nix should not carry vm-specific branching'
fi

grep -Fq 'programs.gpg.enable = true;' den/aspects/features/gpg.nix
grep -Fq 'services.gpg-agent = {' den/aspects/features/gpg.nix

grep -Fq '071F6FE39FC26713930A702401E5F9A947FA8F5C' den/aspects/hosts/vm-aarch64.nix
grep -Fq '9317B542250D33B34C41F62831D3B9C9754C0F5B' den/aspects/hosts/macbook-pro-m1.nix
grep -Fq '247AE5FC6A838272' den/aspects/hosts/wsl.nix
grep -Fq 'gpg-preset-passphrase-login' den/aspects/hosts/vm-aarch64.nix
```

Update `tests/den/wsl.sh` so it checks the WSL rbw-related service settings from `den/aspects/hosts/wsl.nix` instead of `den/aspects/features/secrets.nix`.

**Step 2: Run test to verify it fails**

Run: `bash tests/gpg-preset-passphrase.sh && bash tests/den/wsl.sh`

Expected: FAIL because `gpg.nix` and `secrets.nix` still carry VM/WSL-specific branches.

**Step 3: Write minimal implementation**

Keep only shared behavior in `gpg.nix` and `secrets.nix`:

```nix
# den/aspects/features/gpg.nix
programs.gpg.enable = true;
services.gpg-agent = {
  enable = true;
  defaultCacheTtl = 31536000;
  maxCacheTtl = 31536000;
};
programs.git.signing.signByDefault = true;
```

```nix
# den/aspects/features/secrets.nix
sops.defaultSopsFile = generated.requireFile "secrets.yaml";
services.tailscale.enable = true;
users.mutableUsers = false;
```

Move the host-specific deltas into host aspects:

- `vm-aarch64`: VM signing key, preset-passphrase helper package/service, `allow-preset-passphrase`, rbw-config service with `pinentry-wayprompt`
- `macbook-pro-m1`: Darwin signing key, Darwin `gpg.program`, one-second gpg-agent TTLs, Touch ID pinentry program
- `wsl`: legacy signing key, rbw-config service with `pinentry-tty`

**Step 4: Run test to verify it passes**

Run: `bash tests/gpg-preset-passphrase.sh && bash tests/den/wsl.sh`

Expected: PASS

**Step 5: Commit**

```bash
git add tests/gpg-preset-passphrase.sh tests/den/wsl.sh \
  den/aspects/features/gpg.nix den/aspects/features/secrets.nix \
  den/aspects/hosts/vm-aarch64.nix den/aspects/hosts/macbook-pro-m1.nix den/aspects/hosts/wsl.nix
git -c commit.gpgsign=false commit -m "refactor: move gpg and secret host deltas to host aspects" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 7: Remove migration/task commentary and run the full regression suite

**Files:**
- Modify: `tests/den/no-legacy.sh`
- Modify: `den/default.nix`
- Modify: `den/hosts.nix`
- Modify: `den/aspects/features/*.nix`
- Modify: `den/aspects/hosts/*.nix`

**Step 1: Write the failing test**

Add a cleanup guard to `tests/den/no-legacy.sh`:

```bash
if rg -n 'Migrated from|Task [0-9]+|den migration|legacy Home Manager|temporary legacy bridge' \
  den/default.nix den/hosts.nix den/aspects >/dev/null; then
  fail 'den config still contains migration/task commentary'
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/den/no-legacy.sh`

Expected: FAIL because several den files still contain migration/task comments.

**Step 3: Write minimal implementation**

Delete migration-era comments from the den config files you touched. Keep only comments that explain real behavior or constraints, for example:

- why `home-manager.backupFileExtension = "backup"` exists
- why VMware shared folders need particular mount options
- why a service intentionally runs only on one host

Do not leave comments that explain the migration history.

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/den/no-legacy.sh && \
bash tests/den/flake-smoke.sh && \
bash tests/den/host-schema.sh && \
bash tests/den/identity.sh && \
bash tests/den/home-manager-core.sh && \
bash tests/den/devtools.sh && \
bash tests/den/linux-core.sh && \
bash tests/den/vm-desktop.sh && \
bash tests/den/darwin.sh && \
bash tests/den/wsl.sh && \
bash tests/gpg-preset-passphrase.sh
```

Expected: PASS

**Step 5: Commit**

```bash
git add tests/den/no-legacy.sh den/default.nix den/hosts.nix den/aspects
git -c commit.gpgsign=false commit -m "refactor: clean up den config comments" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
