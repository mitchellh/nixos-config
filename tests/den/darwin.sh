#!/usr/bin/env bash
# tests/den/darwin.sh
#
# Verifies Task 9 of the den migration:
#   - den/aspects/features/darwin-core.nix  (new)
#   - den/aspects/features/homebrew.nix     (new)
#   - den/aspects/features/launchd.nix      (new)
#   - den/aspects/hosts/macbook-pro-m1.nix wires the new aspects
#   - machines/macbook-pro-m1.nix and users/m/darwin.nix no longer own the
#     migrated settings

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# ---------------------------------------------------------------------------
# Static structure checks — new aspect files must exist
# ---------------------------------------------------------------------------

test -f den/aspects/features/darwin-core.nix \
  || { echo "FAIL: den/aspects/features/darwin-core.nix missing" >&2; exit 1; }
test -f den/aspects/features/darwin-desktop.nix \
  || { echo "FAIL: den/aspects/features/darwin-desktop.nix missing" >&2; exit 1; }
test -f den/aspects/features/homebrew.nix \
  || { echo "FAIL: den/aspects/features/homebrew.nix missing" >&2; exit 1; }
test -f den/aspects/features/launchd.nix \
  || { echo "FAIL: den/aspects/features/launchd.nix missing" >&2; exit 1; }

grep -Fq 'system.stateVersion = 5;'           den/aspects/features/darwin-core.nix
grep -Fq 'nix.enable = false;'                den/aspects/features/darwin-core.nix
grep -Fq 'services.openssh.enable = true;'    den/aspects/features/darwin-core.nix
grep -Fq 'openssh.authorizedKeys.keyFiles'    den/aspects/features/darwin-core.nix
grep -Fq 'system.defaults.CustomUserPreferences' den/aspects/features/darwin-desktop.nix
grep -Fq 'services.yabai.enable = true;'      den/aspects/features/darwin-desktop.nix
grep -Fq 'services.skhd = {'                   den/aspects/features/darwin-desktop.nix
grep -Fq 'homebrew.enable = true;'            den/aspects/features/homebrew.nix
grep -Fq '../../../dotfiles/common/opencode/modules/darwin.nix' den/aspects/features/launchd.nix
grep -Fq 'launchd.user.agents.uniclip'        den/aspects/features/launchd.nix
grep -Fq 'AW_IMPORT_SRC'                      den/aspects/features/launchd.nix

grep -Fq 'den.aspects.darwin-core'            den/aspects/hosts/macbook-pro-m1.nix
grep -Fq 'den.aspects.darwin-desktop'         den/aspects/hosts/macbook-pro-m1.nix
grep -Fq 'den.aspects.homebrew'               den/aspects/hosts/macbook-pro-m1.nix
grep -Fq 'den.aspects.launchd'                den/aspects/hosts/macbook-pro-m1.nix

# ---------------------------------------------------------------------------
# Guard: migrated system-level items must no longer remain in
# machines/macbook-pro-m1.nix
# ---------------------------------------------------------------------------

darwin_machine=machines/macbook-pro-m1.nix
if [ -e "$darwin_machine" ]; then
  for item in \
    'system.stateVersion = 5;' \
    'nix.enable = false;' \
    'services.openssh' \
    'security.pam.services.sudo_local'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$darwin_machine" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $darwin_machine still contains '$item' (should be in darwin-core.nix)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Guard: migrated Darwin user/system items must no longer remain in
# users/m/darwin.nix
# ---------------------------------------------------------------------------

darwin_user=users/m/darwin.nix
if [ -e "$darwin_user" ]; then
  for item in \
    'homebrew = {' \
    'system.primaryUser = "m";' \
    'launchd.user.agents.uniclip' \
    'launchd.user.agents.openwebui' \
    'launchd.user.agents.activitywatch-sync-ios-screentime-to-aw' \
    'imports = [ ./opencode/modules/darwin.nix ];' \
    'system.defaults.CustomUserPreferences' \
    'services.yabai.enable = true;' \
    'services.skhd = {'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$darwin_user" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $darwin_user still contains '$item' (should be in a den aspect)" >&2
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

nix_eval_apply_raw() {
  local attr="$1" apply="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix_generated_eval --raw --apply "$apply" "$attr" 2>"$err_file"); then
    echo "FAIL: nix_generated_eval apply failed for '$attr' with:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Live eval: Darwin system settings
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.nix.enable")
[ "$actual" = "false" ] \
  || { echo "FAIL: nix.enable: expected false, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.services.openssh.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.openssh.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.services.openssh.extraConfig")
printf '%s' "$actual" | grep -Fq 'ListenAddress 192.168.130.1' \
  || { echo "FAIL: services.openssh.extraConfig missing ListenAddress 192.168.130.1" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.homebrew.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: homebrew.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.system.primaryUser")
[ "$actual" = "m" ] \
  || { echo "FAIL: system.primaryUser: expected m, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.system.stateVersion")
[ "$actual" = "5" ] \
  || { echo "FAIL: system.stateVersion: expected 5, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.system.defaults.CustomUserPreferences.\"com.apple.finder\".AppleShowAllFiles")
[ "$actual" = "true" ] \
  || { echo "FAIL: system.defaults.CustomUserPreferences.com.apple.finder.AppleShowAllFiles: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.services.yabai.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.yabai.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.services.skhd.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.skhd.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.pkgs" 'pkgs: if pkgs ? uniclip then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: darwin system pkgs missing overlay package uniclip" >&2; exit 1; }

actual=$(nix_eval_apply_raw ".#nixosConfigurations.vm-aarch64.pkgs" 'pkgs: if pkgs ? uniclip then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: vm system pkgs missing overlay package uniclip" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents.uniclip.serviceConfig.RunAtLoad")
[ "$actual" = "true" ] \
  || { echo "FAIL: launchd.user.agents.uniclip.serviceConfig.RunAtLoad: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents" 'agents: if agents ? "opencode-serve" then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: launchd.user.agents.opencode-serve missing from Darwin config" >&2; exit 1; }

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents" 'agents: if agents ? "opencode-web" then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: launchd.user.agents.opencode-web missing from Darwin config" >&2; exit 1; }

echo "All darwin checks passed."
