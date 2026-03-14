#!/bin/bash
# WSL NixOS installer - build and output the WSL installer tarball
# Usage: sh <(curl -sL https://smallstepman.github.io/wsl.sh)

set -euo pipefail

NIX_CONFIG_DIR="$HOME/.config/nix"
GENERATED_DIR="${GENERATED_DIR:-$HOME/.local/share/nix-config-generated}"

if [ ! -d "$NIX_CONFIG_DIR" ]; then
    echo "==> Cloning config repo..."
    mkdir -p "$HOME/.config"
    git clone https://github.com/smallstepman/smallstepman.github.io "$NIX_CONFIG_DIR"
fi

cd "$NIX_CONFIG_DIR"
mkdir -p "$GENERATED_DIR"
# shellcheck source=../scripts/external-input-flake.sh
. "$NIX_CONFIG_DIR/scripts/external-input-flake.sh"
WRAPPER=$(GENERATED_INPUT_DIR="$GENERATED_DIR" NIX_CONFIG_DIR="$NIX_CONFIG_DIR" mk_wrapper_flake)

echo "==> Building WSL installer..."
nix build "path:$WRAPPER#nixosConfigurations.wsl.config.system.build.installer" --no-write-lock-file
echo "==> Done. Installer at: $NIX_CONFIG_DIR/result"
