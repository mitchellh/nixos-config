# Den Framework Rewrite Design

## Problem

This repository currently builds three targets (`vm-aarch64`, `macbook-pro-m1`, and `wsl`) through a handwritten composition layer in `flake.nix` and `lib/mksystem.nix`, then spreads behavior across machine modules, OS-specific user modules, and a large shared Home Manager file. The setup works, but the architectural intent is hidden behind manual module wiring, repeated platform branching, and a large amount of configuration that is only understandable by tracing conditionals across files.

The goal of this rewrite is to replace that handwritten composition with a den-native host/user/aspect graph while preserving the current per-target behavior exactly. The end state should be visibly den-shaped from the top of the tree down, not a legacy layout with den sprinkled on top.

## Approved Constraints

- Optimize for the full end-state den architecture of the main repo, not a thin compatibility layer.
- Prefer idiomatic den structure even when it significantly changes the repo shape.
- Preserve current behavior 1:1 for each target, even when that behavior differs across Darwin, the Linux VM, and WSL.
- Use a hybrid vertical-slice migration: create the final den structure up front, then move behavior slice by slice.
- Respect the repository's security boundary: generated/secret material may be made visible to local Nix evaluation in an authorized private checkout or worktree, but must never be committed into the public repo.

## Source Material Studied

### Current repo

- `flake.nix`
- `lib/mksystem.nix`
- `machines/vm-aarch64.nix`
- `machines/vm-shared.nix`
- `machines/macbook-pro-m1.nix`
- `machines/wsl.nix`
- `users/m/nixos.nix`
- `users/m/darwin.nix`
- `users/m/home-manager.nix`
- `tests/gpg-preset-passphrase.sh`

### Den docs

- `guides/from-flake-to-den.mdx`
- `guides/migrate.mdx`
- `guides/declare-hosts.mdx`
- `guides/home-manager.mdx`
- `guides/batteries.mdx`
- `reference/schema.mdx`
- `reference/output.mdx`

## Design Goals

1. Replace `lib/mksystem.nix` with den host declarations and den-generated outputs.
2. Replace repo-local platform booleans (`darwin`, `wsl`, `isWSL`, `currentSystemName`) with den context and explicit schema metadata.
3. Break the current large user/home-manager configuration into feature-first aspects with explicit ownership.
4. Keep machine-specific configuration only where there is a true hardware or host-specific quirk.
5. Preserve private/generated files outside the committed repo while still allowing local evaluation in authorized worktrees.

## Non-Goals

- Rewriting hardware-generated files under `machines/hardware/`.
- Changing behavior intentionally during the migration.
- Turning secrets or generated artifacts into tracked files.
- Building a standalone den-only home configuration outside the existing multi-host flake.

## Target Architecture

The final architecture should be centered around a top-level `den/` directory:

```text
den/
  default.nix
  hosts.nix
  legacy.nix            # temporary migration bridge only
  aspects/
    features/
      identity.nix
      shell-git.nix
      gpg.nix
      editors-devtools.nix
      ai-tools.nix
      linux-core.nix
      linux-desktop.nix
      secrets.nix
      vmware.nix
      darwin-core.nix
      homebrew.nix
      launchd.nix
      wsl.nix
    hosts/
      vm-aarch64.nix
      macbook-pro-m1.nix
      wsl.nix
    users/
      m.nix
tests/
  den/
    flake-smoke.sh
    host-schema.sh
    identity.sh
    home-manager-core.sh
    devtools.sh
    linux-core.sh
    vm-desktop.sh
    darwin.sh
    wsl.sh
    no-legacy.sh
```

### `flake.nix`

`flake.nix` becomes responsible for only four things:

1. Inputs and overlays.
2. Evaluating the den module graph.
3. Exporting `nixosConfigurations` and `darwinConfigurations` from `den.flake`.
4. Keeping non-den outputs that should remain manual, such as the `packages.*.collect-secrets` outputs.

### `den/hosts.nix`

`den/hosts.nix` becomes the source of truth for:

- the three managed hosts,
- their target systems,
- the user graph,
- WSL/VMware/platform metadata,
- any host-level metadata needed by aspects.

The final declarations should look conceptually like:

```nix
den.hosts.aarch64-linux.vm-aarch64.users.m = { };
den.hosts.x86_64-linux.wsl.users.m = { };
den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };
```

with explicit metadata attached to hosts and/or users rather than inferred from ad-hoc function arguments.

### `den/default.nix`

`den/default.nix` owns den-wide defaults:

- `imports = [ inputs.den.flakeModule ];`
- shared den schema (`den.schema.host`, `den.schema.user`)
- default user classes (`homeManager`)
- shared batteries:
  - `den.provides.define-user`
  - `den.provides.primary-user`
  - `den.provides.hostname`
  - `den.provides.user-shell`
- any den-global includes required to keep evaluation predictable

### `den/aspects/features/*`

Feature aspects hold reusable behavior, independent of the old file layout. Their job is to express concerns, not mimic directories:

- `identity.nix` - host names, user definitions, primary-user rules, base shells/home paths.
- `shell-git.nix` - shells, aliases, git identity, shared CLI behavior.
- `gpg.nix` - signing keys, pinentry selection, preset-passphrase behavior, host-specific GPG rules.
- `editors-devtools.nix` / `ai-tools.nix` - packages, editor integration, developer tools, AI tooling.
- `linux-core.nix` - Nix settings, Linux services, base packages, nix-ld, shared Linux system behavior.
- `linux-desktop.nix` - Wayland/Niri/Mango/Noctalia, HM Wayland config, Linux desktop services.
- `secrets.nix` - sops/sopsidy wiring and secret ownership.
- `vmware.nix` - VMware HGFS mounts, guest integration, Linux VM quirks.
- `darwin-core.nix` - Determinate-Nix-specific settings, shell init, Touch ID sudo, host sshd.
- `homebrew.nix` - casks, brews, MAS apps.
- `launchd.nix` - Darwin launchd agents and other user-service wiring.
- `wsl.nix` - WSL enablement and WSL-specific behavior.

### `den/aspects/hosts/*`

Host aspect files remain thin and explicit. They should mostly do two things:

1. select the feature aspects that apply to the host, and
2. keep the true host-specific one-off configuration that should not be shared elsewhere.

This preserves the final den graph in a readable form without reintroducing a new `mkSystem` abstraction.

### `den/aspects/users/m.nix`

`m.nix` becomes the user-specific aggregator:

- includes the feature aspects owned by user `m`,
- carries only the metadata or includes that genuinely belong to the user,
- avoids cross-platform branching except where den context or declared metadata requires it.

## Metadata Model

The rewrite should add a small, explicit schema rather than reintroducing hidden branching through free-form strings everywhere.

### Host metadata

Recommended fields:

- `profile` - coarse host profile such as `vm`, `darwin-laptop`, or `wsl`.
- `wsl.enable` - drives WSL-specific behavior.
- `vmware.enable` - drives VMware-specific behavior.
- `graphical.enable` - distinguishes GUI Linux VM from non-GUI WSL.
- `home-manager.sharedModules` - explicit place for the shared HM module list now assembled in `lib/mksystem.nix`.

### User metadata

Recommended fields:

- `shell` - preferred login shell.
- `gpg.profile` - signing/pinentry profile for the current user on a host.
- `homeRoot` - when den batteries need a stable path override.

The point of the schema is not to model every detail. It is to move the current implicit decisions into explicit metadata that aspects can read.

## Composition Model

The new evaluation path is:

```text
flake.nix
  -> evalModules over den/
  -> den.hosts + den.schema + den.aspects
  -> den context pipeline
  -> host/user/homeManager class dispatch
  -> den.flake.{nixosConfigurations,darwinConfigurations}
```

This replaces:

```text
flake.nix
  -> lib/mksystem.nix
  -> manual module list
  -> OS booleans and _module.args
  -> machine/user/home-manager files
```

## Migration Strategy

Although the end-state architecture is fully den-native, the migration should use one temporary bridge: `den/legacy.nix`.

`den/legacy.nix` should temporarily load untouched legacy modules through `den.provides.import-tree` so that:

- the final den structure exists immediately,
- the repo keeps working while slices move one by one,
- each migrated slice can delete ownership from the legacy tree instead of requiring a big-bang rewrite.

This file is transitional infrastructure, not architecture. It must be deleted at the end of the migration.

## Ownership Mapping From Current Files

- `lib/mksystem.nix` -> replaced by `den/default.nix`, `den/hosts.nix`, and host/user aspect aggregation.
- `machines/vm-shared.nix` -> split across `linux-core.nix`, `linux-desktop.nix`, `secrets.nix`, and host-level Linux VM aspects.
- `machines/vm-aarch64.nix` -> `vmware.nix` plus `hosts/vm-aarch64.nix`.
- `machines/macbook-pro-m1.nix` -> `darwin-core.nix` plus `hosts/macbook-pro-m1.nix`.
- `machines/wsl.nix` -> `wsl.nix` plus `hosts/wsl.nix`.
- `users/m/nixos.nix` -> `identity.nix` and `linux-core.nix`.
- `users/m/darwin.nix` -> `identity.nix`, `homebrew.nix`, `launchd.nix`, and `darwin-core.nix`.
- `users/m/home-manager.nix` -> `shell-git.nix`, `gpg.nix`, `editors-devtools.nix`, `ai-tools.nix`, `linux-desktop.nix`, and any remaining user-scoped feature aspects.

## Verification Model

Because the goal is 1:1 behavior, every slice must have an explicit owner and an explicit regression check. The verification model should include:

1. **Structure checks** for the den scaffolding and host declarations.
2. **Nix evaluation checks** for host/user outputs and selected options.
3. **Existing regression checks** such as `bash tests/gpg-preset-passphrase.sh`.
4. **Target-specific parity checks** for:
   - `vm-aarch64`
   - `macbook-pro-m1`
   - `wsl`

Any command that requires `machines/secrets.yaml` or generated private artifacts must run only in an authorized local checkout/worktree where those files are made visible to Nix evaluation without committing them. The migration must preserve that boundary.

## Major Risks

### 1. `users/m/home-manager.nix` is both large and multi-concern

This is the highest-risk file because it combines packages, shell behavior, GPG, Wayland, services, and host-specific behavior in one place. The rewrite should move it in vertical slices and keep a regression check for each slice before deleting the original block.

### 2. Secret-backed evaluation is intentionally non-public

The repo already relies on private/generated material for some evaluations. Den must not change that security posture. The migration should treat those files as local execution prerequisites, not tracked inputs.

### 3. Shared Home Manager modules are currently assembled by hand

The current repo uses an explicit shared module list, including a Darwin-only extra Niri HM module. This must be encoded explicitly in host metadata or host aspects so the Linux/Darwin behavior stays aligned with den's class dispatch.

### 4. Launchd and VMware behavior are both host-specific and security-sensitive

These slices should migrate late, after the den scaffolding, identity, shell, and GPG slices are already proven.

## End-State Summary

The finished repo should make its architecture obvious:

- `flake.nix` is thin.
- `den/hosts.nix` names the systems and users.
- `den/default.nix` defines global den behavior and schema.
- `den/aspects/features/*` owns reusable behavior.
- `den/aspects/hosts/*` and `den/aspects/users/*` are thin aggregators with only true one-off logic.
- legacy files and the temporary import-tree bridge are gone.

That gives the repo a den-native shape without sacrificing the current target-specific behavior or the existing secret boundary.
