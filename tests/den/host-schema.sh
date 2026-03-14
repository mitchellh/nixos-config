#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

require_contains() {
  local needle=$1
  local file=$2
  local message=$3
  if ! grep -Fq "$needle" "$file"; then
    echo "ERROR: $message" >&2
    exit 1
  fi
}

require_contains 'den.hosts.aarch64-linux.vm-aarch64.users.m' den/hosts.nix 'vm-aarch64 user declaration is missing from den/hosts.nix'
require_contains 'den.hosts.aarch64-darwin.macbook-pro-m1.users.m' den/hosts.nix 'macbook-pro-m1 user declaration is missing from den/hosts.nix'
require_contains 'den.hosts.x86_64-linux.wsl.users.m' den/hosts.nix 'wsl user declaration is missing from den/hosts.nix'
require_contains 'den._.wsl' den/default.nix 'den/default.nix must include the built-in den WSL battery'
require_contains 'den.ctx.hm-host.includes' den/default.nix 'den.ctx.hm-host.includes must remain intact in den/default.nix'
if grep -Fq 'options.profile' den/default.nix; then
  echo 'ERROR: profile should be removed from den/default.nix' >&2
  exit 1
fi
require_contains 'options.vmware.enable' den/default.nix 'vmware.enable must remain in den/default.nix until later tasks migrate its consumers'
require_contains 'options.graphical.enable' den/default.nix 'graphical.enable must remain in den/default.nix until later tasks migrate its consumers'
# wsl.enable is provided by den upstream in modules/aspects/provides/wsl.nix;
# our schema must NOT redeclare it
if grep -Fq 'options.wsl.enable' den/default.nix; then
  echo 'ERROR: options.wsl.enable must not be declared in den/default.nix (conflicts with den upstream)' >&2
  exit 1
fi
# The wsl host must use the built-in den wsl.enable setting
require_contains 'den.hosts.x86_64-linux.wsl.wsl.enable = true' den/hosts.nix 'wsl host must keep den-provided wsl.enable in den/hosts.nix'
require_contains 'den.hosts.aarch64-linux.vm-aarch64.vmware.enable = true' den/hosts.nix 'vm-aarch64 must retain vmware.enable host assignment until later tasks'
require_contains 'den.hosts.aarch64-linux.vm-aarch64.graphical.enable = true' den/hosts.nix 'vm-aarch64 must retain graphical.enable host assignment until later tasks'
if rg -n 'profile = ' den/hosts.nix >/dev/null; then
  echo 'ERROR: den/hosts.nix should drop only profile host assignments in Task 1' >&2
  exit 1
fi
