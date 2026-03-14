#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# --- Static structure checks ---

# identity feature aspect must include the key user-context batteries
grep -Fq 'den.provides.define-user' den/aspects/features/identity.nix
grep -Fq 'den.provides.primary-user' den/aspects/features/identity.nix
grep -Fq 'den.provides.user-shell' den/aspects/features/identity.nix

# user m aspect must reference the identity aspect
grep -Fq 'den.aspects.identity' den/aspects/users/m.nix

# vm-aarch64 host aspect must include the hostname battery
grep -Fq 'den.provides.hostname' den/aspects/hosts/vm-aarch64.nix

# hosts.nix must carry the explicit vm-macbook hostname
grep -Fq 'vm-macbook' den/hosts.nix

# host aspect files must exist for all three hosts
test -f den/aspects/hosts/macbook-pro-m1.nix
test -f den/aspects/hosts/wsl.nix

# --- Live nix_generated_eval checks ---

# Helper: run nix_generated_eval, surface the real error output on failure instead of
# silently swallowing it with 2>/dev/null.  stderr is routed to a temp file so
# that it never contaminates the captured stdout; on failure it is forwarded to
# stderr so the caller sees the actual error.
_nix_eval() {
  local fmt="$1" attr="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix_generated_eval "$fmt" "$attr" 2>"$err_file"); then
    echo "FAIL: nix_generated_eval '$attr' failed with:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
  cat "$err_file" >&2   # pass warnings through without polluting stdout
  rm -f "$err_file"
  printf '%s' "$out"
}

nix_eval_raw()  { _nix_eval --raw  "$1"; }
nix_eval_json() { _nix_eval --json "$1"; }

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.networking.hostName")
expected="vm-macbook"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: vm-aarch64 hostName: expected '$expected', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.system.primaryUser")
expected="m"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: macbook-pro-m1 primaryUser: expected '$expected', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.wsl.defaultUser")
expected="m"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: wsl defaultUser: expected '$expected', got '$actual'" >&2
  exit 1
fi

# --- Provenance checks: confirm den modules are the source, not legacy files ---
# These assert that definitionsWithLocations points into den's aspect modules,
# encoding the controller's verification that the identity slice is active
# through den rather than through any legacy flat machine files.

defs=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.options.networking.hostName.definitionsWithLocations")
if ! printf '%s' "$defs" | grep -q 'hostname.nix'; then
  echo "FAIL: vm-aarch64 hostName not defined by modules/aspects/provides/hostname.nix" >&2
  echo "definitionsWithLocations: $defs" >&2
  exit 1
fi

defs=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.options.system.primaryUser.definitionsWithLocations")
if ! printf '%s' "$defs" | grep -q 'primary-user.nix'; then
  echo "FAIL: macbook-pro-m1 primaryUser not defined by modules/aspects/provides/primary-user.nix" >&2
  echo "definitionsWithLocations: $defs" >&2
  exit 1
fi

defs=$(nix_eval_json ".#nixosConfigurations.wsl.options.wsl.defaultUser.definitionsWithLocations")
if ! printf '%s' "$defs" | grep -q 'provides/wsl.nix'; then
  echo "FAIL: wsl defaultUser not defined by modules/aspects/provides/wsl.nix" >&2
  echo "definitionsWithLocations: $defs" >&2
  exit 1
fi

echo "All identity checks passed."
