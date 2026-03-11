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
[[ "$mac_extra_config" != *ignore-cache-for-signing* ]] || fail 'macbook-pro-m1 should use short agent TTLs instead of ignore-cache-for-signing'

mac_default_cache_ttl=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.defaultCacheTtl)
[[ "$mac_default_cache_ttl" == "1" ]] || fail 'macbook-pro-m1 should keep gpg-agent cache entries for only 1 second'

mac_max_cache_ttl=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.maxCacheTtl)
[[ "$mac_max_cache_ttl" == "1" ]] || fail 'macbook-pro-m1 should cap gpg-agent cache entries at 1 second'

vm_helper_present=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.packages --apply 'pkgs: builtins.any (pkg: (pkg.name or "") == "gpg-preset-passphrase-login") pkgs')
[[ "$vm_helper_present" == "true" ]] || fail 'vm-aarch64 helper script package is missing'

grep -Fq 'vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";' "$source_file" || fail 'vm-aarch64 helper script does not target the VM signing key'
grep -Fq 'printf '\''%s'\'' "$passphrase" |' "$source_file" || fail 'vm-aarch64 helper script does not pipe the passphrase via stdin'
grep -Fq 'mapfile -t keygrips < <(' "$source_file" || fail 'vm-aarch64 helper script does not collect all signing keygrips'
grep -Fq "for keygrip in \"''\${keygrips[@]}\"; do" "$source_file" || fail 'vm-aarch64 helper script does not preset every resolved keygrip'
grep -Fq 'gpg-preset-passphrase --preset "$keygrip"' "$source_file" || fail 'vm-aarch64 helper script does not use supported gpg-preset-passphrase arguments'
if grep -Fq -- '--passphrase-fd' "$source_file"; then
  fail 'vm-aarch64 helper script still uses unsupported --passphrase-fd'
fi
if grep -Fq -- '--passphrase "$passphrase"' "$source_file"; then
  fail 'vm-aarch64 helper script should not expose the passphrase via command-line arguments'
fi
if grep -Fq "\$1 == \"grp\" { print \$10; exit }" "$source_file"; then
  fail 'vm-aarch64 helper script still assumes the first grp line is the only relevant keygrip'
fi

grep -Fq ']) ++ (lib.optionals (currentSystemName == "vm-aarch64") [' "$source_file" || fail 'helper script is not guarded to vm-aarch64 in source'
grep -Fq '(lib.optionalString (currentSystemName == "vm-aarch64") "allow-preset-passphrase")' "$source_file" || fail 'allow-preset-passphrase is not guarded to vm-aarch64 in source'

vm_service_present=$(nix_eval_json --expr 'let flake = builtins.getFlake (toString ./.); in flake.nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services ? gpg-preset-passphrase-login')
[[ "$vm_service_present" == "true" ]] || fail 'vm-aarch64 systemd user service is missing'

vm_service_type=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.Type)
[[ "$vm_service_type" == "oneshot" ]] || fail 'vm-aarch64 systemd user service is not oneshot'

vm_exec_start=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.ExecStart)
[[ "$vm_exec_start" == *gpg-preset-passphrase-login* ]] || fail 'vm-aarch64 systemd user service does not invoke the helper script'

vm_service_restart=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.Restart)
[[ "$vm_service_restart" == "on-failure" ]] || fail 'vm-aarch64 systemd user service does not retry after rbw is unlocked'

vm_service_restart_sec=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.RestartSec)
[[ "$vm_service_restart_sec" == "30" ]] || fail 'vm-aarch64 systemd user service does not wait 30 seconds between retries'

vm_service_after=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Unit.After)
[[ "$vm_service_after" == *default.target* ]] || fail 'vm-aarch64 systemd user service is not ordered after login'
[[ "$vm_service_after" == *rbw-config.service* ]] || fail 'vm-aarch64 systemd user service no longer waits for rbw config'

vm_service_wanted_by=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Install.WantedBy)
[[ "$vm_service_wanted_by" == *default.target* ]] || fail 'vm-aarch64 systemd user service is not enabled for login-time startup'

mac_service_present=$(nix_eval_json --expr 'let flake = builtins.getFlake (toString ./.); in flake.darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.systemd.user.services ? gpg-preset-passphrase-login')
[[ "$mac_service_present" == "false" ]] || fail 'macbook-pro-m1 unexpectedly defines the systemd user service'

grep -Fq 'systemd.user.services.gpg-preset-passphrase-login = lib.mkIf (currentSystemName == "vm-aarch64") {' "$source_file" || fail 'systemd user service is not guarded to vm-aarch64 in source'
grep -Fq 'Restart = "on-failure";' "$source_file" || fail 'systemd user service is missing retry behavior'
grep -Fq 'RestartSec = 30;' "$source_file" || fail 'systemd user service is missing retry delay'

printf 'PASS: gpg preset passphrase configuration looks correct\n'
