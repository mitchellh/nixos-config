#!/usr/bin/env bash
# tests/den/linux-core.sh
#
# Verifies Task 7 of the den migration:
#   - den/aspects/features/linux-core.nix
#   - den/aspects/features/secrets.nix
#   - den/aspects/hosts/vm-aarch64.nix wires both aspects
#   - users/m/nixos.nix and machines/vm-shared.nix no longer own migrated settings

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# ---------------------------------------------------------------------------
# Static structure checks — new files must exist
# ---------------------------------------------------------------------------

test -f den/aspects/features/linux-core.nix \
  || { echo "FAIL: den/aspects/features/linux-core.nix missing" >&2; exit 1; }
test -f den/aspects/features/secrets.nix \
  || { echo "FAIL: den/aspects/features/secrets.nix missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# linux-core.nix ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'boot.kernelPackages'            den/aspects/features/linux-core.nix
grep -Fq 'nix.package'                    den/aspects/features/linux-core.nix
grep -Fq 'services.openssh.enable'        den/aspects/features/linux-core.nix
grep -Fq 'networking.networkmanager'      den/aspects/features/linux-core.nix
grep -Fq 'programs.nix-ld'               den/aspects/features/linux-core.nix
grep -Fq 'environment.localBinInPath'     den/aspects/features/linux-core.nix
grep -Fq 'programs.zsh.enable'            den/aspects/features/linux-core.nix
grep -Fq 'services.flatpak.enable'        den/aspects/features/linux-core.nix
grep -Fq 'system.stateVersion'            den/aspects/features/linux-core.nix
grep -Fq 'i18n.defaultLocale'             den/aspects/features/linux-core.nix
grep -Fq 'security.sudo'                  den/aspects/features/linux-core.nix
grep -Fq 'networking.firewall'            den/aspects/features/linux-core.nix
grep -Fq 'fonts.fontDir.enable'           den/aspects/features/linux-core.nix

# ---------------------------------------------------------------------------
# secrets.nix ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'sops.defaultSopsFile'           den/aspects/features/secrets.nix
grep -Fq 'sops.age'                       den/aspects/features/secrets.nix
grep -Fq 'tailscale/auth-key'             den/aspects/features/secrets.nix
grep -Fq 'user/hashed-password'           den/aspects/features/secrets.nix
grep -Fq 'rbw-config'                     den/aspects/features/secrets.nix
grep -Fq 'services.tailscale'             den/aspects/features/secrets.nix
grep -Fq 'users.mutableUsers'             den/aspects/features/secrets.nix

# ---------------------------------------------------------------------------
# vm-aarch64 host aspect wires the new features
# ---------------------------------------------------------------------------

grep -Fq 'den.aspects.linux-core'         den/aspects/hosts/vm-aarch64.nix
grep -Fq 'den.aspects.secrets'            den/aspects/hosts/vm-aarch64.nix

# ---------------------------------------------------------------------------
# vm-aarch64 host aspect owns host-specific remnants
# ---------------------------------------------------------------------------

grep -Fq 'openwebui-local-proxy'          den/aspects/hosts/vm-aarch64.nix
grep -Fq 'authorizedKeys'                 den/aspects/hosts/vm-aarch64.nix
grep -Fq 'extraGroups'                    den/aspects/hosts/vm-aarch64.nix
grep -Fq 'sops.hostPubKey'                den/aspects/hosts/vm-aarch64.nix

# Scope guard: host pubkey is host-specific and wl-clipboard stays desktop-scoped.
if grep -Ev '^[[:space:]]*#' den/aspects/features/secrets.nix | grep -Fq 'sops.hostPubKey'; then
  echo "FAIL: den/aspects/features/secrets.nix should not own sops.hostPubKey" >&2
  exit 1
fi
if grep -Ev '^[[:space:]]*#' den/aspects/features/linux-core.nix | grep -Fq 'wl-clipboard'; then
  echo "FAIL: den/aspects/features/linux-core.nix should not own wl-clipboard" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Guard: migrated items must no longer remain in users/m/nixos.nix
# ---------------------------------------------------------------------------

nixos_file=users/m/nixos.nix

if [ -e "$nixos_file" ]; then
  for item in 'environment.localBinInPath' 'programs.zsh.enable' 'programs.nix-ld'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$nixos_file" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $nixos_file still contains '$item' (should be in linux-core.nix)" >&2
      exit 1
    fi
  done
fi

# sops secrets and tailscale should be in secrets.nix, not nixos.nix
if [ -e "$nixos_file" ]; then
  for item in 'sops.secrets' 'services.tailscale'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$nixos_file" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $nixos_file still contains '$item' (should be in secrets.nix)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Guard: migrated items must no longer remain in machines/vm-shared.nix
# ---------------------------------------------------------------------------

vmshared=machines/vm-shared.nix

if [ -e "$vmshared" ]; then
  for item in 'services.openssh.enable' 'networking.networkmanager.enable' \
               'sops.defaultSopsFile' 'services.tailscale.enable' \
               'sops.hostPubKey' 'boot.kernelPackages' 'environment.localBinInPath' \
               'programs.nix-ld' 'programs.zsh.enable'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$vmshared" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $vmshared still contains '$item' (should be in aspect)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Live nix_generated_eval helper
# ---------------------------------------------------------------------------

_nix_eval() {
  local fmt="$1" attr="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix_generated_eval "$fmt" "$attr" 2>"$err_file"); then
    echo "FAIL: nix_generated_eval '$attr' failed with:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}

nix_eval_raw()  { _nix_eval --raw  "$1"; }
nix_eval_json() { _nix_eval --json "$1"; }

# ---------------------------------------------------------------------------
# Live eval: vm-aarch64 system settings
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.services.openssh.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.openssh.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.services.tailscale.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.tailscale.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.programs.nix-ld.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: programs.nix-ld.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.environment.localBinInPath")
[ "$actual" = "true" ] \
  || { echo "FAIL: environment.localBinInPath: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.users.mutableUsers")
[ "$actual" = "false" ] \
  || { echo "FAIL: users.mutableUsers: expected false, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.security.sudo.wheelNeedsPassword")
[ "$actual" = "true" ] \
  || { echo "FAIL: security.sudo.wheelNeedsPassword: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.networking.networkmanager.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: networking.networkmanager.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.networking.firewall.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: networking.firewall.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.services.snap.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.snap.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.sops.age.generateKey")
[ "$actual" = "true" ] \
  || { echo "FAIL: sops.age.generateKey: expected true, got $actual" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Live eval: users.users.m
# ---------------------------------------------------------------------------

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.users.users.m.hashedPasswordFile")
printf '%s' "$actual" | grep -q 'hashed-password' \
  || { echo "FAIL: hashedPasswordFile missing 'hashed-password' token, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.users.users.m.openssh.authorizedKeys.keyFiles")
printf '%s' "$actual" | grep -q 'host-authorized-keys' \
  || { echo "FAIL: authorizedKeys.keyFiles missing host-authorized-keys, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.users.users.m.extraGroups")
printf '%s' "$actual" | grep -q '"lxd"' \
  || { echo "FAIL: extraGroups missing lxd, got '$actual'" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Live eval: sops defaultSopsFile must resolve through the generated input
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.sops.defaultSopsFile")
printf '%s' "$actual" | grep -q 'secrets.yaml' \
  || { echo "FAIL: sops.defaultSopsFile does not mention secrets.yaml, got '$actual'" >&2; exit 1; }

echo "All linux-core checks passed."
