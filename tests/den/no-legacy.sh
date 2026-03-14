#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

nix_eval_raw() {
  nix_generated_eval --raw "$@"
}

nix_eval_json() {
  nix_generated_eval --json "$@"
}

for legacy_path in \
  den/legacy.nix \
  lib/mksystem.nix \
  machines \
  machines/vm-aarch64.nix \
  machines/vm-shared.nix \
  machines/macbook-pro-m1.nix \
  machines/wsl.nix \
  users/m \
  users/m/home-manager.nix \
  users/m/nixos.nix \
  users/m/darwin.nix; do
  if [ -e "$legacy_path" ]; then
    fail "$legacy_path still exists"
  fi
done

for required_dir in \
  dotfiles/common \
  dotfiles/by-host/darwin \
  dotfiles/by-host/vm \
  dotfiles/by-host/wsl; do
  if [ ! -d "$required_dir" ]; then
    fail "$required_dir missing"
  fi
done

tracked_generated=$(git ls-files 'generated/*')
[ -z "$tracked_generated" ] \
  || fail 'generated/ artifacts are still tracked in git'

grep -Fq 'lib.mkOutputs' flake.nix \
  || fail 'flake.nix must export lib.mkOutputs'

grep -Fq 'generated.requireFile "secrets.yaml"' den/aspects/features/secrets.nix \
  || fail 'den/aspects/features/secrets.nix must source secrets.yaml from generated input'
grep -Fq '(generated.requireFile "mac-host-authorized-keys")' den/aspects/features/darwin-core.nix \
  || fail 'den/aspects/features/darwin-core.nix must source mac-host-authorized-keys from generated input'
grep -Fq 'generated.readFile "vm-age-pubkey"' den/aspects/hosts/vm-aarch64.nix \
  || fail 'den/aspects/hosts/vm-aarch64.nix must source vm-age-pubkey from generated input'
grep -Fq '(generated.requireFile "host-authorized-keys")' den/aspects/hosts/vm-aarch64.nix \
  || fail 'den/aspects/hosts/vm-aarch64.nix must source host-authorized-keys from generated input'
grep -Fxq 'generated/' .gitignore \
  || fail '.gitignore must ignore local generated/ copies'

grep -Fq 'inputs.den.flakeModule' den/default.nix \
  || fail 'den/default.nix no longer imports inputs.den.flakeModule'
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' den/mk-config-outputs.nix \
  || fail 'den/mk-config-outputs.nix must build system outputs'
grep -Fq 'nixpkgs.overlays = overlays;' den/default.nix \
  || fail 'den/default.nix must own global nixpkgs overlays'
grep -Fq 'nixpkgs.config.allowUnfree = true;' den/default.nix \
  || fail 'den/default.nix must own global allowUnfree policy'
if rg -n \
  'inputs\.(sops-nix|sopsidy|nix-snapd|niri|disko|mangowc|noctalia|nixos-wsl)\.nixosModules' \
  den/default.nix >/dev/null; then
  fail 'den/default.nix still centralizes Linux-only flake-module imports'
fi
grep -Fq 'inputs.sops-nix.nixosModules.sops' den/aspects/features/secrets.nix \
  || fail 'secrets aspect must own sops-nix module import'
grep -Fq 'inputs.sopsidy.nixosModules.default' den/aspects/features/secrets.nix \
  || fail 'secrets aspect must own sopsidy module import'
grep -Fq 'inputs.nix-snapd.nixosModules.default' den/aspects/features/linux-core.nix \
  || fail 'linux-core aspect must own nix-snapd module import'
grep -Fq 'inputs.niri.nixosModules.niri' den/aspects/features/linux-desktop.nix \
  || fail 'linux-desktop aspect must own niri module import'
grep -Fq 'inputs.mangowc.nixosModules.mango' den/aspects/features/linux-desktop.nix \
  || fail 'linux-desktop aspect must own mangowc module import'
grep -Fq 'inputs.noctalia.nixosModules.default' den/aspects/features/linux-desktop.nix \
  || fail 'linux-desktop aspect must own noctalia module import'
grep -Fq 'inputs.nixos-wsl.nixosModules.wsl' den/aspects/features/wsl.nix \
  || fail 'wsl aspect must own nixos-wsl module import'
grep -Fq 'inputs.disko.nixosModules.disko' den/aspects/hosts/vm-aarch64.nix \
  || fail 'vm-aarch64 host aspect must own disko module import'
if grep -R -Fq --exclude 'no-legacy.sh' 'den/legacy.nix' \
  flake.nix \
  den \
  README.md \
  AGENTS.md \
  docs/secrets.md \
  docs/clipboard-sharing.md; then
  fail 'repository still references den/legacy.nix after cleanup'
fi
if rg -n --glob '!tests/den/no-legacy.sh' \
  'users/m/|machines/generated|machines/secrets\.yaml|machines/hardware/' \
  den README.md AGENTS.md docs/*.md docs/*.sh flake.nix >/dev/null; then
  fail 'repository still references users/m or machines/* runtime paths after layout cleanup'
fi

vm_hostname=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.networking.hostName)
[[ "$vm_hostname" == "vm-macbook" ]] || fail "vm-aarch64 hostname is '$vm_hostname', expected vm-macbook"

vm_root_mount=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.disko.devices.disk.main.content.partitions.root.content.mountpoint)
[[ "$vm_root_mount" == "/" ]] || fail "vm-aarch64 disko root mountpoint is '$vm_root_mount', expected /"

darwin_primary_user=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser)
[[ "$darwin_primary_user" == "m" ]] || fail "macbook-pro-m1 primary user is '$darwin_primary_user', expected m"

wsl_enabled=$(nix_eval_json .#nixosConfigurations.wsl.config.wsl.enable)
[[ "$wsl_enabled" == "true" ]] || fail "wsl.enable is '$wsl_enabled', expected true"

printf 'PASS: legacy composition files are gone and den outputs still evaluate\n'
