#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

nix_eval_raw() {
  nix --extra-experimental-features 'nix-command flakes' eval --impure --raw "$@"
}

nix_eval_json() {
  nix --extra-experimental-features 'nix-command flakes' eval --impure --json "$@"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

source_file=users/m/home-manager.nix

vm_extra_config=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.services.gpg-agent.extraConfig)
[[ "$vm_extra_config" == *allow-preset-passphrase* ]] || fail 'vm-aarch64 gpg-agent does not allow preset passphrases'

mac_extra_config=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.extraConfig)
[[ "$mac_extra_config" != *allow-preset-passphrase* ]] || fail 'macbook-pro-m1 unexpectedly allows preset passphrases'
[[ "$mac_extra_config" == *pinentry-program* ]] || fail 'macbook-pro-m1 lost pinentry-program configuration'

vm_helper_present=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.packages --apply 'pkgs: builtins.any (pkg: (pkg.name or "") == "gpg-preset-passphrase-login") pkgs')
[[ "$vm_helper_present" == "true" ]] || fail 'vm-aarch64 helper script package is missing'

grep -Fq ']) ++ (lib.optionals (currentSystemName == "vm-aarch64") [' "$source_file" || fail 'helper script is not guarded to vm-aarch64 in source'
grep -Fq '(lib.optionalString (currentSystemName == "vm-aarch64") "allow-preset-passphrase")' "$source_file" || fail 'allow-preset-passphrase is not guarded to vm-aarch64 in source'

vm_service_present=$(nix_eval_json --expr 'let flake = builtins.getFlake (toString ./.); in flake.nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services ? gpg-preset-passphrase-login')
[[ "$vm_service_present" == "true" ]] || fail 'vm-aarch64 systemd user service is missing'

vm_service_type=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.Type)
[[ "$vm_service_type" == "oneshot" ]] || fail 'vm-aarch64 systemd user service is not oneshot'

vm_exec_start=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.ExecStart)
[[ "$vm_exec_start" == *gpg-preset-passphrase-login* ]] || fail 'vm-aarch64 systemd user service does not invoke the helper script'

mac_service_present=$(nix_eval_json --expr 'let flake = builtins.getFlake (toString ./.); in flake.darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.systemd.user.services ? gpg-preset-passphrase-login')
[[ "$mac_service_present" == "false" ]] || fail 'macbook-pro-m1 unexpectedly defines the systemd user service'

grep -Fq 'systemd.user.services.gpg-preset-passphrase-login = lib.mkIf (currentSystemName == "vm-aarch64") {' "$source_file" || fail 'systemd user service is not guarded to vm-aarch64 in source'

printf 'PASS: gpg preset passphrase configuration looks correct\n'
