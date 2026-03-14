#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.users.m' den/hosts.nix
grep -Fq 'den.hosts.aarch64-darwin.macbook-pro-m1.users.m' den/hosts.nix
grep -Fq 'den.hosts.x86_64-linux.wsl.users.m' den/hosts.nix
grep -Fq 'options.profile' den/default.nix
grep -Fq 'options.vmware.enable' den/default.nix
grep -Fq 'options.graphical.enable' den/default.nix
grep -A4 'options\.profile' den/default.nix | grep -Fq 'description'
# wsl.enable is provided by den upstream in modules/aspects/provides/wsl.nix;
# our schema must NOT redeclare it
if grep -Fq 'options.wsl.enable' den/default.nix; then
  echo "ERROR: options.wsl.enable must not be declared in den/default.nix (conflicts with den upstream)" >&2
  exit 1
fi
# The wsl host must use the built-in den wsl.enable setting
grep -Fq 'den.hosts.x86_64-linux.wsl.wsl.enable = true' den/hosts.nix
