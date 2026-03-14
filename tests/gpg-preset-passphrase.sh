#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# shellcheck source=lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

nix_eval_raw() {
  nix_generated_eval --raw "$@"
}

nix_eval_json() {
  nix_generated_eval --json "$@"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# GPG/signing configuration is now owned by the den gpg aspect, not the legacy
# home-manager.nix.  All source-level assertions target the new aspect file.
source_file=den/aspects/features/gpg.nix

# --- Static: den aspect must exist ---
test -f "$source_file" || fail 'den/aspects/features/gpg.nix does not exist'

# Den-native host context must be used (no legacy currentSystemName)
grep -Fq 'isVM' "$source_file" || fail 'gpg.nix does not use den-native isVM host context'
grep -Fq 'isDarwin' "$source_file" || fail 'gpg.nix does not use den-native isDarwin host context'
if grep -Fq 'currentSystemName' "$source_file"; then
  fail 'gpg.nix still uses legacy currentSystemName — must use den host context (isVM/isDarwin) instead'
fi

# Signing keys must be present
grep -Fq 'vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";' "$source_file" || fail 'vm-aarch64 signing key not found in gpg.nix'

# VM-only guards use isVM (den-native), not currentSystemName
grep -Fq '(lib.optionalString isVM "allow-preset-passphrase")' "$source_file" || fail 'allow-preset-passphrase is not guarded by isVM in gpg.nix'
grep -Fq 'lib.optionals isVM [' "$source_file" || fail 'helper script package is not guarded by isVM in gpg.nix'
grep -Fq 'systemd.user.services.gpg-preset-passphrase-login = lib.mkIf isVM {' "$source_file" || fail 'systemd user service is not guarded by isVM in gpg.nix'

# Helper script implementation details (behavior must be preserved verbatim)
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

# Systemd service retry settings must be preserved
grep -Fq 'Restart = "on-failure";' "$source_file" || fail 'systemd user service is missing retry behavior'
grep -Fq 'RestartSec = 30;' "$source_file" || fail 'systemd user service is missing retry delay'

# --- Legacy home-manager.nix must no longer own GPG/signing config ---
if [ -e users/m/home-manager.nix ]; then
  if grep -Fq 'services.gpg-agent' users/m/home-manager.nix; then
    fail 'users/m/home-manager.nix still owns services.gpg-agent — must be in den gpg aspect'
  fi
  if grep -Fq 'signByDefault' users/m/home-manager.nix; then
    fail 'users/m/home-manager.nix still owns signByDefault — must be in den gpg aspect'
  fi
  if grep -Fq 'signing.key' users/m/home-manager.nix; then
    fail 'users/m/home-manager.nix still owns git signing.key — must be in den gpg aspect'
  fi
  if grep -Fq 'gpgPresetPassphraseLogin' users/m/home-manager.nix; then
    fail 'users/m/home-manager.nix still references gpgPresetPassphraseLogin — must be in den gpg aspect'
  fi
fi

# --- Live nix_generated_eval: gpg-agent behavior ---

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

# --- Live nix_generated_eval: helper script package ---

vm_helper_present=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.packages --apply 'pkgs: builtins.any (pkg: (pkg.name or "") == "gpg-preset-passphrase-login") pkgs')
[[ "$vm_helper_present" == "true" ]] || fail 'vm-aarch64 helper script package is missing'

# --- Live nix_generated_eval: systemd user service ---

vm_service_present=$(nix_generated_eval --json --apply 'services: services ? "gpg-preset-passphrase-login"' ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services")
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

mac_service_present=$(nix_generated_eval --json --apply 'services: services ? "gpg-preset-passphrase-login"' ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.systemd.user.services")
[[ "$mac_service_present" == "false" ]] || fail 'macbook-pro-m1 unexpectedly defines the systemd user service'

# --- Live nix_generated_eval: git signing ---

vm_signing_key=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.signing.key)
[[ "$vm_signing_key" == "071F6FE39FC26713930A702401E5F9A947FA8F5C" ]] || fail "vm-aarch64 git signing key is '$vm_signing_key', expected 071F6FE39FC26713930A702401E5F9A947FA8F5C"

vm_sign_by_default=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.signing.signByDefault)
[[ "$vm_sign_by_default" == "true" ]] || fail 'vm-aarch64 git signByDefault is not true'

mac_signing_key=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.signing.key)
[[ "$mac_signing_key" == "9317B542250D33B34C41F62831D3B9C9754C0F5B" ]] || fail "macbook-pro-m1 git signing key is '$mac_signing_key', expected 9317B542250D33B34C41F62831D3B9C9754C0F5B"

mac_sign_by_default=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.signing.signByDefault)
[[ "$mac_sign_by_default" == "true" ]] || fail 'macbook-pro-m1 git signByDefault is not true'

vm_gpg_program=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.gpg.program)
[[ "$vm_gpg_program" == *gpg* ]] || fail "vm-aarch64 git gpg.program '$vm_gpg_program' does not reference gpg"

mac_gpg_program=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.settings.gpg.program)
[[ "$mac_gpg_program" == "/opt/homebrew/bin/gpg" ]] || fail "macbook-pro-m1 git gpg.program is '$mac_gpg_program', expected /opt/homebrew/bin/gpg"

printf 'PASS: gpg preset passphrase configuration looks correct\n'
