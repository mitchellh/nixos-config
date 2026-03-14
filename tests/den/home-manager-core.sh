#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# --- Static structure checks ---

# shell-git feature aspect must exist
test -f den/aspects/features/shell-git.nix
test -f den/aspects/features/home-base.nix

# den docs polish: HM host-level wiring should live on hm-host, not host.
grep -Fq 'den.ctx.hm-host.includes' den/default.nix
if grep -Fq 'den.ctx.host.includes' den/default.nix; then
  echo "FAIL: den/default.nix still centralizes host wiring under den.ctx.host.includes" >&2
  exit 1
fi

# shell-git must set essential HM programs
grep -Fq 'programs.git = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.zsh = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.oh-my-posh = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.direnv = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.atuin = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.zoxide = {' den/aspects/features/shell-git.nix
grep -Fq 'programs.gh = {' den/aspects/features/shell-git.nix

# shell-git must set session variables
grep -Fq 'EDITOR' den/aspects/features/shell-git.nix

# home-base must own the remaining user-level HM config
grep -Fq 'programs.rbw = lib.mkIf isLinux' den/aspects/features/home-base.nix
grep -Fq '"grm/repos.yaml"' den/aspects/features/home-base.nix
grep -Fq 'ghostty-bin' den/aspects/features/home-base.nix
grep -Fq '"wezterm/wezterm.lua"' den/aspects/features/home-base.nix
grep -Fq 'den.aspects.home-base' den/aspects/users/m.nix

# shell-git must reference the git alias for 'g'
grep -Eq '(^|[[:space:]])g[[:space:]]*=[[:space:]]*"git";' den/aspects/features/shell-git.nix

# user m aspect must include shell-git
grep -Fq 'den.aspects.shell-git' den/aspects/users/m.nix

non_comment_shell_git=$(grep -Ev '^[[:space:]]*#' den/aspects/features/shell-git.nix)

# signing-key/GPG must NOT have moved into shell-git.nix
if printf '%s\n' "$non_comment_shell_git" | grep -Eq 'gitSigningKey|signByDefault|signing\\.key|gpg\\.program|services\\.gpg-agent'; then
  echo "FAIL: signing/GPG config found in shell-git.nix — it must stay in home-manager.nix" >&2
  exit 1
fi

# legacy home-manager.nix should no longer own shell/git or residual HM entries
if [ -e users/m/home-manager.nix ]; then
  legacy_home_manager=$(grep -Ev '^[[:space:]]*#' users/m/home-manager.nix || true)
  for legacy_pkg in bat eza fd fnm fzf jq kubecolor kubectl rbw ripgrep tig zoxide; do
    if printf '%s\n' "$legacy_home_manager" | grep -Eq "^[[:space:]]*pkgs\\.${legacy_pkg}\\b"; then
      echo "FAIL: users/m/home-manager.nix still owns pkgs.${legacy_pkg}" >&2
      exit 1
    fi
  done
  if printf '%s\n' "$legacy_home_manager" | grep -Fq 'writeShellScriptBin "git-credential-github"'; then
    echo "FAIL: users/m/home-manager.nix still owns git-credential-github" >&2
    exit 1
  fi
  for item in \
    '"grm/repos.yaml"' \
    '"wezterm/wezterm.lua"' \
    '"activitywatch/scripts"' \
    '"kanata-tray"' \
    '"kanata"' \
    'programs.rbw' \
    'ghostty-bin' \
    'sentry-cli'; do
    if printf '%s\n' "$legacy_home_manager" | grep -Fq "$item"; then
      echo "FAIL: users/m/home-manager.nix still contains '$item' (should be in den/aspects/features/home-base.nix)" >&2
      exit 1
    fi
  done
fi

# --- Live nix_generated_eval helper (borrowed from identity.sh) ---

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

# --- Live eval: vm-aarch64 (NixOS/Linux) ---

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.useGlobalPkgs")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 home-manager.useGlobalPkgs: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.useUserPackages")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 home-manager.useUserPackages: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.backupFileExtension")
if [ "$actual" != "backup" ]; then
  echo "FAIL: vm-aarch64 home-manager.backupFileExtension: expected 'backup', got '$actual'" >&2
  exit 1
fi

vm_wayprompt_drv=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.wayprompt.package.drvPath")
vm_global_wayprompt_drv=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64._module.args.pkgs.wayprompt.drvPath")
if [ "$vm_wayprompt_drv" != "$vm_global_wayprompt_drv" ]; then
  echo "FAIL: vm-aarch64 home-manager wayprompt drvPath diverges from host pkgs.wayprompt" >&2
  echo "home-manager: $vm_wayprompt_drv" >&2
  echo "host: $vm_global_wayprompt_drv" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 programs.git.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 programs.zsh.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.sessionVariables.EDITOR")
if [ "$actual" != "nvim" ]; then
  echo "FAIL: vm-aarch64 EDITOR: expected 'nvim', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.stateVersion")
if [ "$actual" != "18.09" ]; then
  echo "FAIL: vm-aarch64 home.stateVersion: expected '18.09', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.init.defaultBranch")
if [ "$actual" != "main" ]; then
  echo "FAIL: vm-aarch64 git init.defaultBranch: expected 'main', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.github.user")
if [ "$actual" != "smallstepman" ]; then
  echo "FAIL: vm-aarch64 github.user: expected 'smallstepman', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.oh-my-posh.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 programs.oh-my-posh.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: vm-aarch64 programs.rbw.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_apply_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.settings.pinentry" 'pinentry: toString pinentry')
if [[ "$actual" != *pinentry-wayprompt* ]]; then
  echo "FAIL: vm-aarch64 rbw pinentry: expected pinentry-wayprompt, got '$actual'" >&2
  exit 1
fi

# Check the 'g = "git"' alias is present
actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases.g")
if [ "$actual" != "git" ]; then
  echo "FAIL: vm-aarch64 zsh alias g: expected 'git', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.aliases")
if ! printf '%s' "$actual" | grep -q '"prettylog"'; then
  echo "FAIL: vm-aarch64 git aliases missing prettylog" >&2
  echo "aliases: $actual" >&2
  exit 1
fi

# Linux-only aliases present on vm-aarch64 (non-WSL Linux)
zsh_aliases=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases")
if ! printf '%s' "$zsh_aliases" | grep -q '"pbcopy"'; then
  echo "FAIL: vm-aarch64 zsh shellAliases missing Linux 'pbcopy'" >&2
  echo "shellAliases: $zsh_aliases" >&2
  exit 1
fi

# Note: vm-aarch64 home.packages cannot be evaluated from Darwin as of Task 6
# because programs.doom-emacs loads nix-doom-emacs-unstraightened which uses
# IFD (import-from-derivation) requiring an aarch64-linux builder.
# Package presence is verified through the darwin config (same package set).
# vm_packages check removed; covered by darwin check below.

# --- Live eval: macbook-pro-m1 (Darwin) ---

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.useGlobalPkgs")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 home-manager.useGlobalPkgs: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.useUserPackages")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 home-manager.useUserPackages: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.backupFileExtension")
if [ "$actual" != "backup" ]; then
  echo "FAIL: macbook-pro-m1 home-manager.backupFileExtension: expected 'backup', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 programs.git.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 programs.zsh.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.sessionVariables.EDITOR")
if [ "$actual" != "nvim" ]; then
  echo "FAIL: macbook-pro-m1 EDITOR: expected 'nvim', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.stateVersion")
if [ "$actual" != "18.09" ]; then
  echo "FAIL: macbook-pro-m1 home.stateVersion: expected '18.09', got '$actual'" >&2
  exit 1
fi

# Darwin DISPLAY workaround
actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.sessionVariables.DISPLAY")
if [ "$actual" != "nixpkgs-390751" ]; then
  echo "FAIL: macbook-pro-m1 DISPLAY: expected 'nixpkgs-390751', got '$actual'" >&2
  exit 1
fi

# Darwin aliases: niks/nikt present, NOT Linux-only pbcopy
mac_aliases=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.shellAliases")
if ! printf '%s' "$mac_aliases" | grep -q '"niks"'; then
  echo "FAIL: macbook-pro-m1 zsh shellAliases missing 'niks'" >&2
  echo "shellAliases: $mac_aliases" >&2
  exit 1
fi
if printf '%s' "$mac_aliases" | grep -q '"pbcopy"'; then
  echo "FAIL: macbook-pro-m1 zsh shellAliases has Linux-only 'pbcopy'" >&2
  echo "shellAliases: $mac_aliases" >&2
  exit 1
fi

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.oh-my-posh.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 programs.oh-my-posh.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

# Darwin git credential helper enabled via gh
actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.gh.gitCredentialHelper.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 programs.gh.gitCredentialHelper.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

darwin_packages=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages")
for pkg in bat eza fnm jq rbw ripgrep tig; do
  if ! printf '%s' "$darwin_packages" | grep -q -- "-$pkg"; then
    echo "FAIL: macbook-pro-m1 home.packages missing $pkg" >&2
    echo "packages: $darwin_packages" >&2
    exit 1
  fi
done
if printf '%s' "$darwin_packages" | grep -q -- '-git-credential-github'; then
  echo "FAIL: macbook-pro-m1 home.packages should not include git-credential-github" >&2
  echo "packages: $darwin_packages" >&2
  exit 1
fi

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile" 'cfg: if cfg ? "grm/repos.yaml" then "true" else "false"')
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 missing xdg.configFile.\"grm/repos.yaml\"" >&2
  exit 1
fi

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile.\"grm/repos.yaml\".source" 'source: toString source')
if [[ "$actual" != *dotfiles/common/grm-repos.yaml ]]; then
  echo "FAIL: macbook-pro-m1 grm/repos.yaml source unexpected: '$actual'" >&2
  exit 1
fi

for key in \
  'wezterm/wezterm.lua' \
  'activitywatch/scripts' \
  'kanata-tray' \
  'kanata'; do
  actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile" "cfg: if cfg ? \"${key}\" then \"true\" else \"false\"")
  if [ "$actual" != "true" ]; then
    echo "FAIL: macbook-pro-m1 missing xdg.configFile.\"${key}\"" >&2
    exit 1
  fi
done

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages" 'pkgs: if builtins.any (pkg: builtins.match ".*ghostty.*" (pkg.name or "") != null) pkgs then "true" else "false"')
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 home.packages missing ghostty" >&2
  exit 1
fi

actual=$(nix_eval_apply_raw ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages" 'pkgs: if builtins.any (pkg: builtins.match ".*sentry-cli.*" (pkg.name or "") != null) pkgs then "true" else "false"')
if [ "$actual" != "true" ]; then
  echo "FAIL: macbook-pro-m1 home.packages missing sentry-cli" >&2
  exit 1
fi

# --- Live eval: wsl (NixOS Linux, WSL) ---

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.useGlobalPkgs")
if [ "$actual" != "true" ]; then
  echo "FAIL: wsl home-manager.useGlobalPkgs: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.useUserPackages")
if [ "$actual" != "true" ]; then
  echo "FAIL: wsl home-manager.useUserPackages: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_raw ".#nixosConfigurations.wsl.config.home-manager.backupFileExtension")
if [ "$actual" != "backup" ]; then
  echo "FAIL: wsl home-manager.backupFileExtension: expected 'backup', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.git.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: wsl programs.git.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.zsh.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: wsl programs.zsh.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

# WSL should not pick up Darwin-only aliases
wsl_aliases=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.zsh.shellAliases")
if printf '%s' "$wsl_aliases" | grep -q '"pinentry"'; then
  echo "FAIL: wsl zsh shellAliases has Darwin-only 'pinentry'" >&2
  exit 1
fi

# gh credential helper disabled on Linux (WSL uses rbw-based approach)
actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.gh.gitCredentialHelper.enable")
if [ "$actual" != "false" ]; then
  echo "FAIL: wsl programs.gh.gitCredentialHelper.enable: expected 'false', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.rbw.enable")
if [ "$actual" != "true" ]; then
  echo "FAIL: wsl programs.rbw.enable: expected 'true', got '$actual'" >&2
  exit 1
fi

actual=$(nix_eval_apply_raw ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.rbw.settings.pinentry" 'pinentry: toString pinentry')
if [[ "$actual" != *pinentry-tty* ]]; then
  echo "FAIL: wsl rbw pinentry: expected pinentry-tty, got '$actual'" >&2
  exit 1
fi

# Note: wsl home.packages cannot be evaluated from Darwin as of Task 6
# because programs.doom-emacs uses IFD requiring an x86_64-linux builder.
# Package presence is verified through the darwin config.
# wsl_packages check removed; covered by darwin check above.

# Guard: signing key NOT in shell-git.nix (static file check already done above, belt-and-suspenders)
if printf '%s\n' "$non_comment_shell_git" | grep -Eq 'gitSigningKey|signByDefault|signing\\.key|gpg\\.program|services\\.gpg-agent'; then
  echo "FAIL: signing config leaked into shell-git.nix" >&2
  exit 1
fi

echo "All home-manager-core checks passed."
