#!/usr/bin/env bash
# tests/den/wsl.sh
#
# Verifies Task 10 of the den migration:
#   - den/aspects/features/wsl.nix       (new)
#   - den/aspects/hosts/wsl.nix wires the new WSL aspect
#   - machines/wsl.nix no longer owns the migrated WSL-specific settings
#   - den.provides.wsl continues to own wsl.defaultUser

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# ---------------------------------------------------------------------------
# Static structure checks
# ---------------------------------------------------------------------------

test -f den/aspects/features/wsl.nix \
  || { echo "FAIL: den/aspects/features/wsl.nix missing" >&2; exit 1; }

grep -Fq 'wsl.enable = true;'                 den/aspects/features/wsl.nix
grep -Fq 'wslConf.automount.root = "/mnt";'   den/aspects/features/wsl.nix
grep -Fq 'startMenuLaunchers = true;'         den/aspects/features/wsl.nix
grep -Fq 'package = pkgs.nixVersions.latest;' den/aspects/features/wsl.nix
grep -Fq 'system.stateVersion = "23.05";'     den/aspects/features/wsl.nix
grep -Fq 'den.aspects.wsl-system'             den/aspects/hosts/wsl.nix

# Guard: defaultUser is still owned by den's built-in WSL provider.
if grep -Eq 'defaultUser[[:space:]]*=' den/aspects/features/wsl.nix; then
  echo "FAIL: den/aspects/features/wsl.nix should not redefine wsl.defaultUser" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Guard: migrated WSL items must no longer remain in machines/wsl.nix
# ---------------------------------------------------------------------------

wsl_machine=machines/wsl.nix
if [ -e "$wsl_machine" ]; then
  for item in \
    'wsl = {' \
    'defaultUser = currentSystemUser;' \
    'nix = {' \
    'system.stateVersion = "23.05";'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$wsl_machine" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $wsl_machine still contains '$item' (should be owned by den WSL wiring)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Live nix_generated_eval helpers
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
# Live eval: WSL config
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.wsl.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: wsl.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.wsl.defaultUser")
[ "$actual" = "m" ] \
  || { echo "FAIL: wsl.defaultUser: expected m, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.wsl.wslConf.automount.root")
[ "$actual" = "/mnt" ] \
  || { echo "FAIL: wsl.wslConf.automount.root: expected /mnt, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.wsl.startMenuLaunchers")
[ "$actual" = "true" ] \
  || { echo "FAIL: wsl.startMenuLaunchers: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.nix.package.version")
expected=$(nix_eval_raw ".#nixosConfigurations.wsl.pkgs.nixVersions.latest.version")
[ "$actual" = "$expected" ] \
  || { echo "FAIL: nix.package.version: expected unstable $expected, got $actual" >&2; exit 1; }

actual=$(nix_eval_json '.#nixosConfigurations.wsl.config.nix.settings."experimental-features"')
printf '%s' "$actual" | grep -q '"nix-command"' \
  || { echo "FAIL: nix.settings.experimental-features missing nix-command, got $actual" >&2; exit 1; }
printf '%s' "$actual" | grep -q '"flakes"' \
  || { echo "FAIL: nix.settings.experimental-features missing flakes, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.nix.extraOptions")
printf '%s' "$actual" | grep -Fq 'keep-outputs = true' \
  || { echo "FAIL: nix.extraOptions missing keep-outputs = true" >&2; exit 1; }
printf '%s' "$actual" | grep -Fq 'keep-derivations = true' \
  || { echo "FAIL: nix.extraOptions missing keep-derivations = true" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.system.stateVersion")
[ "$actual" = "23.05" ] \
  || { echo "FAIL: system.stateVersion: expected 23.05, got $actual" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Provenance checks
# ---------------------------------------------------------------------------

defs=$(nix_eval_json ".#nixosConfigurations.wsl.options.wsl.enable.definitionsWithLocations")
if ! printf '%s' "$defs" | grep -q 'den/aspects/features/wsl.nix'; then
  echo "FAIL: wsl.enable not defined by den/aspects/features/wsl.nix" >&2
  echo "definitionsWithLocations: $defs" >&2
  exit 1
fi

defs=$(nix_eval_json ".#nixosConfigurations.wsl.options.wsl.defaultUser.definitionsWithLocations")
if ! printf '%s' "$defs" | grep -q 'provides/wsl.nix'; then
  echo "FAIL: wsl.defaultUser not defined by den provides/wsl.nix" >&2
  echo "definitionsWithLocations: $defs" >&2
  exit 1
fi

echo "All wsl checks passed."
