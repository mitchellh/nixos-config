#!/usr/bin/env bash
# tests/den/devtools.sh
#
# Verifies Task 6 of the den migration:
#   - den/aspects/features/editors-devtools.nix
#   - den/aspects/features/ai-tools.nix
#   - den/aspects/users/m.nix wires both aspects
#   - users/m/home-manager.nix no longer owns migrated content

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

# ---------------------------------------------------------------------------
# Static structure checks — new files must exist
# ---------------------------------------------------------------------------

test -f den/aspects/features/editors-devtools.nix || { echo "FAIL: den/aspects/features/editors-devtools.nix missing" >&2; exit 1; }
test -f den/aspects/features/ai-tools.nix         || { echo "FAIL: den/aspects/features/ai-tools.nix missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# editors-devtools ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'pkgs.go'                  den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.nodejs_22'           den/aspects/features/editors-devtools.nix
grep -Fq 'programs.doom-emacs'      den/aspects/features/editors-devtools.nix
grep -Fq 'programs.tmux'            den/aspects/features/editors-devtools.nix
grep -Fq 'programs.vscode'          den/aspects/features/editors-devtools.nix
grep -Fq 'programs.lazyvim'         den/aspects/features/editors-devtools.nix
grep -Fq 'programs.go'              den/aspects/features/editors-devtools.nix
grep -Fq 'installWritableTmuxMenus' den/aspects/features/editors-devtools.nix
grep -Fq 'services.emacs'           den/aspects/features/editors-devtools.nix
grep -Fq 'programs.starship'        den/aspects/features/editors-devtools.nix
grep -Fq 'programs.zellij'          den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.devenv'              den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.dust'                den/aspects/features/editors-devtools.nix
grep -Fq 'pkgs.zellij'              den/aspects/features/editors-devtools.nix

# ---------------------------------------------------------------------------
# ai-tools ownership checks
# ---------------------------------------------------------------------------

grep -Fq 'pkgs.llm-agents.copilot-cli'        den/aspects/features/ai-tools.nix
grep -Fq 'programs.opencode'                   den/aspects/features/ai-tools.nix
grep -Fq 'opencodeAwesome'                     den/aspects/features/ai-tools.nix
grep -Fq 'ensureOpencodePackageJsonWritable'   den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.agent-of-empires'               den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.dotagents'                      den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.apm'                            den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.llm-agents.beads'               den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.llm-agents.openspec'            den/aspects/features/ai-tools.nix
grep -Fq 'pkgs.llm-agents.copilot-language-server' den/aspects/features/ai-tools.nix
grep -Fq 'opencode/modules/home-manager.nix'   den/aspects/features/ai-tools.nix

# ---------------------------------------------------------------------------
# user m aspect must wire both new aspects
# ---------------------------------------------------------------------------

grep -Fq 'den.aspects.editors-devtools' den/aspects/users/m.nix
grep -Fq 'den.aspects.ai-tools'         den/aspects/users/m.nix

# ---------------------------------------------------------------------------
# Guard: Task 6 aspects must NOT contain out-of-scope items
# ---------------------------------------------------------------------------

for aspect in den/aspects/features/editors-devtools.nix den/aspects/features/ai-tools.nix; do
  non_comment=$(grep -Ev '^[[:space:]]*#' "$aspect")

  if printf '%s\n' "$non_comment" | grep -Eq 'projectsRoot|niriDeep'; then
    echo "FAIL: $aspect contains projectsRoot/niriDeep — must stay in home-manager.nix" >&2
    exit 1
  fi

  if printf '%s\n' "$non_comment" | grep -Eq 'load_plugins'; then
    echo "FAIL: $aspect contains load_plugins — must stay in home-manager.nix (Task 8)" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Guard: migrated items must no longer appear in users/m/home-manager.nix
# ---------------------------------------------------------------------------

hm=users/m/home-manager.nix

if [ -e "$hm" ]; then
  # Packages fully owned by editors-devtools
  for pkg in nerd-fonts.symbols-only emacs-all-the-icons-fonts devenv websocat bats bws fluxcd kubernetes-helm terragrunt gnumake nodejs_22 gopls; do
    if grep -Eq "^[[:space:]]*pkgs\\.${pkg}\\b" "$hm"; then
      echo "FAIL: $hm still owns pkgs.${pkg}" >&2
      exit 1
    fi
  done

  # programs fully owned by new aspects
  for prog in doom-emacs lazyvim; do
    if grep -Eq "^[[:space:]]*(programs\\.${prog}|programs\\.${prog} =)" "$hm"; then
      echo "FAIL: $hm still owns top-level programs.${prog} block" >&2
      exit 1
    fi
  done

  # opencode program block
  if grep -Eq '^[[:space:]]*programs\.opencode = \{' "$hm"; then
    echo "FAIL: $hm still owns programs.opencode block" >&2
    exit 1
  fi

  # opencodeAwesome let binding
  if grep -Fq 'opencodeAwesome = import' "$hm"; then
    echo "FAIL: $hm still owns opencodeAwesome let binding" >&2
    exit 1
  fi

  # AI agent packages
  for pkg in agent-of-empires gastown dotagents; do
    if grep -Eq "^[[:space:]]*pkgs\\.${pkg}\\b" "$hm"; then
      echo "FAIL: $hm still owns pkgs.${pkg}" >&2
      exit 1
    fi
  done

  if grep -Eq '^[[:space:]]*pkgs\.llm-agents\.' "$hm"; then
    echo "FAIL: $hm still owns pkgs.llm-agents.* entries" >&2
    exit 1
  fi

  # installWritableTmuxMenus activation
  if grep -Fq 'installWritableTmuxMenus' "$hm"; then
    echo "FAIL: $hm still owns installWritableTmuxMenus" >&2
    exit 1
  fi

  # ensureOpencodePackageJsonWritable activation
  if grep -Fq 'ensureOpencodePackageJsonWritable' "$hm"; then
    echo "FAIL: $hm still owns ensureOpencodePackageJsonWritable" >&2
    exit 1
  fi
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
# Live eval: vm-aarch64 (NixOS/Linux)
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.doom-emacs.enable")
[ "$actual" = "true" ] || { echo "FAIL: vm-aarch64 programs.doom-emacs.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.services.emacs.enable")
[ "$actual" = "true" ] || { echo "FAIL: vm-aarch64 services.emacs.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.vscode.enable")
[ "$actual" = "true" ] || { echo "FAIL: vm-aarch64 programs.vscode.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.go.env.GOPATH" 2>/dev/null || echo "")
[ "$actual" = "Documents/go" ] || { echo "FAIL: vm-aarch64 programs.go GOPATH: expected Documents/go, got '$actual'" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.opencode.enable")
[ "$actual" = "true" ] || { echo "FAIL: vm-aarch64 programs.opencode.enable: expected true, got $actual" >&2; exit 1; }

# Note: vm-aarch64 home.packages cannot be evaluated from Darwin because
# Task 6 moved nix-doom-emacs-unstraightened into the den evaluation path.
# That module uses IFD (import-from-derivation) and needs an aarch64-linux
# builder, so package presence is verified via the darwin config below.

# ---------------------------------------------------------------------------
# Live eval: macbook-pro-m1 (Darwin)
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.doom-emacs.enable")
[ "$actual" = "true" ] || { echo "FAIL: macbook-pro-m1 programs.doom-emacs.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.emacs.enable")
[ "$actual" = "false" ] || { echo "FAIL: macbook-pro-m1 services.emacs.enable: expected false (Darwin), got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.vscode.enable")
[ "$actual" = "true" ] || { echo "FAIL: macbook-pro-m1 programs.vscode.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.opencode.enable")
[ "$actual" = "true" ] || { echo "FAIL: macbook-pro-m1 programs.opencode.enable: expected true, got $actual" >&2; exit 1; }

# Darwin packages can be fully evaluated from the test host (aarch64-darwin).
# Use darwin as the canonical package presence test for cross-platform packages.
mac_packages=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages")
printf '%s' "$mac_packages" | grep -q 'copilot' \
  || { echo "FAIL: macbook-pro-m1 home.packages missing copilot-cli" >&2; echo "$mac_packages" >&2; exit 1; }
printf '%s' "$mac_packages" | grep -qE '\-go-[0-9]' \
  || { echo "FAIL: macbook-pro-m1 home.packages missing go" >&2; echo "$mac_packages" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Live eval: wsl (NixOS/Linux, WSL)
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.services.emacs.enable")
[ "$actual" = "true" ] || { echo "FAIL: wsl services.emacs.enable: expected true (WSL is Linux), got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#nixosConfigurations.wsl.config.home-manager.users.m.programs.opencode.enable")
[ "$actual" = "true" ] || { echo "FAIL: wsl programs.opencode.enable: expected true, got $actual" >&2; exit 1; }

# wsl home.packages cannot be fully evaluated from Darwin for the same reason:
# Task 6 moved nix-doom-emacs-unstraightened into the den path, and its IFD
# needs a Linux builder. Package presence is verified through darwin above.

echo "All devtools checks passed."
