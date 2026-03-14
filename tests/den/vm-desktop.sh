#!/usr/bin/env bash
# tests/den/vm-desktop.sh
#
# Verifies Task 8 of the den migration:
#   - den/aspects/features/linux-desktop.nix  (new)
#   - den/aspects/features/vmware.nix         (new)
#   - den/aspects/hosts/vm-aarch64.nix wires both new aspects
#   - machines/vm-shared.nix, machines/vm-aarch64.nix, users/m/home-manager.nix
#     no longer own the migrated settings

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# ---------------------------------------------------------------------------
# Static structure checks — new aspect files must exist
# ---------------------------------------------------------------------------

test -f den/aspects/features/linux-desktop.nix \
  || { echo "FAIL: den/aspects/features/linux-desktop.nix missing" >&2; exit 1; }
test -f den/aspects/features/vmware.nix \
  || { echo "FAIL: den/aspects/features/vmware.nix missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# linux-desktop.nix ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'programs.niri.enable'              den/aspects/features/linux-desktop.nix
grep -Fq 'services.noctalia-shell.enable'    den/aspects/features/linux-desktop.nix
grep -Fq 'services.greetd'                  den/aspects/features/linux-desktop.nix
grep -Fq 'hardware.bluetooth.enable'         den/aspects/features/linux-desktop.nix
grep -Fq 'services.keyd'                     den/aspects/features/linux-desktop.nix
grep -Fq 'i18n.inputMethod'                  den/aspects/features/linux-desktop.nix
grep -Fq 'programs.kitty'                    den/aspects/features/linux-desktop.nix
grep -Fq 'programs.wayprompt'                den/aspects/features/linux-desktop.nix
grep -Fq 'programs.noctalia-shell'           den/aspects/features/linux-desktop.nix
grep -Fq 'programs.librewolf'                den/aspects/features/linux-desktop.nix
grep -Fq 'home.pointerCursor'                den/aspects/features/linux-desktop.nix
grep -Fq 'wl-clipboard'                      den/aspects/features/linux-desktop.nix

# ---------------------------------------------------------------------------
# vmware.nix ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'virtualisation.vmware.guest.enable' den/aspects/features/vmware.nix
grep -Fq '.host:/Projects'                    den/aspects/features/vmware.nix
grep -Fq '.host:/nixos-config'               den/aspects/features/vmware.nix
grep -Fq 'yeetAndYoink.requirePath'           den/aspects/features/vmware.nix
grep -Fq 'src = yeetAndYoink.root;'           den/aspects/features/vmware.nix
grep -Fq 'cargoLock.lockFile = yeetAndYoink.requirePath "Cargo.lock";' den/aspects/features/vmware.nix
grep -Fq 'programs.ssh'                       den/aspects/features/vmware.nix
grep -Fq 'programs.niri.settings'             den/aspects/features/vmware.nix
grep -Fq 'DOCKER_CONTEXT'                     den/aspects/features/vmware.nix
grep -Fq 'NIRI_DEEP_ZELLIJ_BREAK_PLUGIN'     den/aspects/features/vmware.nix
grep -Fq 'load_plugins'                       den/aspects/features/vmware.nix
grep -Fq 'uniclip'                            den/aspects/features/vmware.nix
grep -Fq 'ensureHostDockerContext'            den/aspects/features/vmware.nix
grep -Fq 'mac-host-docker'                   den/aspects/features/vmware.nix
grep -Fq 'external-input-flake.sh'           docs/vm.sh
grep -Fq 'external-input-flake.sh'           den/aspects/features/shell-git.nix
grep -Fq 'git+file://$yeet_dir?dir=plugins/zellij-break' scripts/external-input-flake.sh
grep -Fq 'YEET_AND_YOINK_INPUT_DIR'          den/aspects/features/shell-git.nix

# ---------------------------------------------------------------------------
# vm-aarch64 host aspect wires both new feature aspects
# ---------------------------------------------------------------------------

grep -Fq 'den.aspects.linux-desktop'          den/aspects/hosts/vm-aarch64.nix
grep -Fq 'den.aspects.vmware'                 den/aspects/hosts/vm-aarch64.nix
grep -Fq 'boot.binfmt.emulatedSystems'        den/aspects/hosts/vm-aarch64.nix
grep -Fq 'networking.interfaces.enp2s0.useDHCP' den/aspects/hosts/vm-aarch64.nix
if grep -Fq '../../../machines/hardware/' den/aspects/hosts/vm-aarch64.nix; then
  echo "FAIL: den/aspects/hosts/vm-aarch64.nix still imports machines/hardware/*" >&2
  exit 1
fi

# Scope guard: these are vm-aarch64 host specifics, not VMware-generic settings.
if grep -Ev '^[[:space:]]*#' den/aspects/features/vmware.nix | grep -Eq 'boot\.binfmt\.emulatedSystems|networking\.interfaces\.enp2s0\.useDHCP'; then
  echo "FAIL: den/aspects/features/vmware.nix should not own vm-aarch64-specific binfmt/DHCP settings" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Guard: migrated desktop items must no longer remain in machines/vm-shared.nix
# ---------------------------------------------------------------------------

vmshared=machines/vm-shared.nix
if [ -e "$vmshared" ]; then
  for item in \
    'programs.niri.enable' \
    'services.noctalia-shell.enable' \
    'services.greetd' \
    'programs.mango.enable' \
    'hardware.bluetooth.enable' \
    'services.keyd'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$vmshared" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $vmshared still contains '$item' (should be in linux-desktop.nix)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Guard: migrated VMware items must no longer remain in machines/vm-aarch64.nix
# ---------------------------------------------------------------------------

vmaarch64=machines/vm-aarch64.nix
if [ -e "$vmaarch64" ]; then
  for item in \
    'virtualisation.vmware.guest.enable' \
    '.host:/Projects' \
    '.host:/nixos-config'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$vmaarch64" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $vmaarch64 still contains '$item' (should be in vmware.nix)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Guard: migrated vm-aarch64 host-specific items must no longer remain in
# machines/vm-aarch64.nix
# ---------------------------------------------------------------------------

if [ -e "$vmaarch64" ]; then
  for item in \
    'boot.binfmt.emulatedSystems' \
    'networking.interfaces.enp2s0.useDHCP' \
    './hardware/vm-aarch64.nix' \
    './hardware/disko-vm.nix'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$vmaarch64" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $vmaarch64 still contains '$item' (should be in den/aspects/hosts/vm-aarch64.nix)" >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Guard: migrated HM items must no longer remain in users/m/home-manager.nix
# ---------------------------------------------------------------------------

hm=users/m/home-manager.nix
if [ -e "$hm" ]; then
  for item in \
    'programs.kitty' \
    'programs.ssh' \
    'programs.niri.settings' \
    'programs.wayprompt' \
    'wayland.windowManager.mango' \
    'programs.noctalia-shell' \
    'programs.librewolf' \
    'mozilla.librewolfNativeMessagingHosts' \
    'home.pointerCursor' \
    'createNoctaliaThemeDirs' \
    'ensureHostDockerContext' \
    'activitywatch-watcher-afk' \
    'systemd.user.services.uniclip' \
    'systemd.user.services.pywalfox-boot' \
    'niriDeepZellijBreakPlugin' \
    'DOCKER_CONTEXT'; do
    non_comment=$(grep -Ev '^[[:space:]]*#' "$hm" || true)
    if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
      echo "FAIL: $hm still contains '$item' (should be in aspect)" >&2
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
# Live eval: NixOS system settings
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.programs.niri.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: programs.niri.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.services.noctalia-shell.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.noctalia-shell.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.virtualisation.vmware.guest.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: virtualisation.vmware.guest.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.services.greetd.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.greetd.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.fileSystems.\"/Users/m/Projects\".device")
printf '%s' "$actual" | grep -q '.host:/Projects' \
  || { echo "FAIL: fileSystems./Users/m/Projects.device: expected '.host:/Projects', got '$actual'" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.boot.binfmt.emulatedSystems")
printf '%s' "$actual" | grep -q '"x86_64-linux"' \
  || { echo "FAIL: boot.binfmt.emulatedSystems missing x86_64-linux, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.boot.initrd.availableKernelModules")
printf '%s' "$actual" | grep -q '"nvme"' \
  || { echo "FAIL: boot.initrd.availableKernelModules missing nvme, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.disko.devices.disk.main.content.partitions.root.content.mountpoint")
[ "$actual" = "/" ] \
  || { echo "FAIL: vm-aarch64 disko root mountpoint: expected '/', got '$actual'" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Live eval: home-manager settings
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.kitty.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: home-manager.users.m.programs.kitty.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.ssh.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: home-manager.users.m.programs.ssh.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.wayprompt.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: home-manager.users.m.programs.wayprompt.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.niri.settings.prefer-no-csd")
[ "$actual" = "true" ] \
  || { echo "FAIL: home-manager.users.m.programs.niri.settings.prefer-no-csd: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zellij.settings.load_plugins")
printf '%s' "$actual" | grep -q 'yeet-and-yoink-zellij-break.wasm' \
  || { echo "FAIL: load_plugins does not contain yeet-and-yoink-zellij-break.wasm, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.sessionVariables.DOCKER_CONTEXT")
[ "$actual" = "host-mac" ] \
  || { echo "FAIL: DOCKER_CONTEXT: expected 'host-mac', got '$actual'" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Live eval: WSL should not inherit VM desktop or VMware features
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.virtualisation.vmware.guest.enable")
[ "$actual" = "false" ] \
  || { echo "FAIL: wsl virtualisation.vmware.guest.enable: expected false, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.programs.niri.enable")
[ "$actual" = "false" ] \
  || { echo "FAIL: wsl programs.niri.enable: expected false, got $actual" >&2; exit 1; }

echo "All vm-desktop checks passed."
