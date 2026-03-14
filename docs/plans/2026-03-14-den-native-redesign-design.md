# Den Native Redesign Design

## Problem

The current den rewrite works, but parts of it are still shaped by the migration rather than by den itself. The main issues are generic feature aspects that own host-specific one-offs, repeated `isWSL`/`isVM`/`isGraphical` plumbing, a custom WSL bridge where den already provides one, and den config files that still carry migration/task commentary instead of explaining present-day behavior.

## Approved Constraints

- Do a full den-native restructuring, not a cosmetic cleanup.
- Keep current behavior stable unless a piece of structure is clearly dead scaffolding.
- Remove migration/task/history commentary from den config files.
- Handle WSL through den rather than through repo-local architectural special casing.
- Validate through the existing den tests and flake evaluation flow instead of adding new test infrastructure.

## Source Material Studied

### Current repo

- `den/default.nix`
- `den/hosts.nix`
- `den/aspects/features/ai-tools.nix`
- `den/aspects/features/home-base.nix`
- `den/aspects/features/shell-git.nix`
- `den/aspects/features/gpg.nix`
- `den/aspects/features/secrets.nix`
- `den/aspects/features/linux-desktop.nix`
- `den/aspects/features/vmware.nix`
- `den/aspects/features/wsl.nix`
- `den/aspects/hosts/vm-aarch64.nix`
- `den/aspects/hosts/wsl.nix`

### Den docs

- `explanation/core-principles.mdx`
- `guides/configure-aspects.mdx`
- `guides/home-manager.mdx`
- `reference/batteries.mdx`
- `reference/ctx.mdx`
- `explanation/context-pipeline.mdx`

## Design Goals

1. Make `den/default.nix` own only den-wide policy, schema, and globally relevant batteries/integration hooks.
2. Keep reusable feature aspects generic and push one-off host behavior back to host aspects.
3. Replace repeated host-flag plumbing with den composition wherever that composition already expresses the condition.
4. Use den's built-in WSL support instead of a hand-rolled WSL import bridge.
5. Keep comments only where they explain a real constraint or non-obvious behavior.

## Current Mismatches

1. `den/aspects/features/vmware.nix` mixes reusable VMware guest behavior with vm-aarch64-only Home Manager and first-switch bridge logic.
2. `den/aspects/features/linux-desktop.nix` and `den/aspects/features/vmware.nix` are selected by host composition already, but still re-check `host.graphical.enable` and `host.vmware.enable` internally.
3. Broad user features still carry WSL-only branches even though den already has WSL-aware host schema/context support.
4. `den/aspects/features/wsl.nix` duplicates den's documented WSL support instead of using den's existing host wiring.
5. Some host metadata looks migration-shaped rather than actively useful; keep only the metadata that drives real composition after the refactor.
6. Den config files still contain migration/task commentary that should not survive the redesign.

## Approved Redesign

### 1. `den/default.nix`

`den/default.nix` should remain the home of:

- `imports = [ inputs.den.flakeModule ]`
- shared overlays and unfree policy
- `den.schema.user` defaults
- true global host schema
- Home Manager OS-side wiring on `den.ctx.hm-host`

The Home Manager wiring should stay on `den.ctx.hm-host`, because den's Home Manager docs explicitly place `home-manager.useGlobalPkgs`, `home-manager.useUserPackages`, and related OS-side integration there, and `hm-host` only activates when at least one host user has the `homeManager` class.

The redesign should keep WSL expressed through den's existing host wiring by setting `den.hosts.<system>.wsl.wsl.enable = true`, without adding `den._.wsl` or a custom `den.provides.wsl` alias in `den/default.nix`. `den/default.nix` should also be trimmed so it does not carry verbose migration commentary or schema fields that no longer drive anything.

### 2. Host declarations and metadata

`den/hosts.nix` should stay small and declarative.

- Keep `wsl.enable`, because den's existing WSL support uses it to create the right host context.
- Re-evaluate `profile`, `graphical.enable`, and `vmware.enable` after the refactor:
  - if a field still drives a real reusable decision, keep it;
  - if host-aspect selection fully replaces it, remove it from schema and host declarations.

With only three explicit hosts, host aspect selection should be preferred over extra capability flags whenever the flag no longer buys reuse.

### 3. Feature/host boundary

`den/aspects/features/*` should contain reusable concerns. `den/aspects/hosts/*` should choose which concerns apply to a host and own the one-off behavior that does not generalize.

Concretely:

- `den/aspects/features/vmware.nix` should keep reusable VMware guest behavior only.
- vm-aarch64-only Home Manager/system behavior currently living in `features/vmware.nix` should move into `den/aspects/hosts/vm-aarch64.nix` or a VM-only sub-aspect included from there.
- `den/aspects/features/linux-desktop.nix` should remain the graphical Linux desktop feature, but it should stop self-gating if only graphical hosts include it.
- WSL-specific repo policy should live in a small WSL-owned aspect if needed, while den's existing host wiring owns WSL activation.

### 4. WSL handling

WSL should be expressed through den, not through repeated repo-local `isWSL` plumbing.

The preferred structure is:

- generic user features stay generic;
- WSL-specific deltas live in WSL-owned aspects or host-provided Home Manager/NixOS config;
- the only acceptable `isWSL` bridge is at an external integration edge that literally requires a boolean parameter.

Practical meaning:

- custom WSL system enablement moves from `den/aspects/features/wsl.nix` to den's existing WSL host wiring plus the WSL host aspect;
- WSL-only package/service/pinentry differences move out of broad features like `home-base`, `shell-git`, and `secrets` when they are really host-owned;
- if an imported module still expects `isWSL`, compute it at the import site from host context instead of making it part of the repo's internal architecture.

### 5. Condition handling

The redesign should stop preserving conditionals just because the migration introduced them.

Use den composition first:

- if a host aspect already decides whether `linux-desktop` or `vmware` is present, those aspects should not re-check the same condition internally;
- use den's existing WSL context-driven dispatch for WSL;
- keep ordinary attribute-level conditionals only where a feature genuinely spans multiple host classes and splitting it further would make the design worse.

This keeps den's rule from `core-principles.mdx` in view: the context/composition should express the condition whenever possible.

### 6. Comment policy

Remove migration/task/history comments from den config files. Keep comments only when they explain:

- a real platform constraint,
- a deliberate compatibility bridge that still exists after the redesign,
- or a non-obvious Nix/den behavior worth preserving.

## Expected File-Level Changes

- `den/default.nix`
  - do not add `den._.wsl` or `den.provides.wsl`
  - keep Home Manager wiring on `den.ctx.hm-host`
  - trim dead schema fields if composition makes them redundant
- `den/hosts.nix`
  - keep only metadata still needed after the refactor
- `den/aspects/features/wsl.nix`
  - shrink to repo-specific WSL settings or remove entirely if the battery plus host-owned config makes it unnecessary
- `den/aspects/features/vmware.nix`
  - keep reusable VMware guest behavior only
- `den/aspects/hosts/vm-aarch64.nix`
  - absorb vm-aarch64-only behavior now living in `features/vmware.nix`
- `den/aspects/features/linux-desktop.nix`
  - drop self-gating if host selection already guarantees the context
- `den/aspects/features/{home-base,shell-git,gpg,secrets,ai-tools}.nix`
  - remove migration comments
  - reduce or eliminate WSL/VM branches that are better modeled through den composition

## Validation

- Run the existing den regression suite and flake smoke tests.
- Verify the three target outputs still evaluate/build in the same places they do today.
- Keep structure tests focused on actual architecture rules, not historical wording.
