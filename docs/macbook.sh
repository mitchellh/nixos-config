#!/bin/bash
# Bootstrap a fresh macbook with nix-darwin config
# Usage: bash <(curl -sL https://smallstepman.github.io/macbook.sh)

set -euo pipefail

default_nix_config_dir() {
    local script_dir candidate
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd || pwd)
    candidate=$(cd "$script_dir/.." >/dev/null 2>&1 && pwd || true)
    if [ -n "$candidate" ] && [ -f "$candidate/flake.nix" ]; then
        printf '%s
' "$candidate"
    else
        printf '%s
' "$HOME/.config/nix"
    fi
}

NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$(default_nix_config_dir)}"
GENERATED_DIR="${GENERATED_DIR:-$HOME/.local/share/nix-config-generated}"
HOST_SSH_PUBKEY_FILE="${HOST_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"

die() { echo "error: $*" >&2; exit 1; }

prepare_generated_dataset() {
    [ -f "$HOST_SSH_PUBKEY_FILE" ] || die "SSH public key not found: $HOST_SSH_PUBKEY_FILE"
    mkdir -p "$GENERATED_DIR"
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/host-authorized-keys"
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/mac-host-authorized-keys"
    [ -f "$GENERATED_DIR/secrets.yaml" ] || : > "$GENERATED_DIR/secrets.yaml"
}

echo "==> macbook bootstrap"

# ─── 1. Xcode Command Line Tools ───────────────────────────────────────────
if ! xcode-select -p &>/dev/null; then
    echo "==> Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "    Waiting for Xcode CLT installation to complete..."
    until xcode-select -p &>/dev/null; do sleep 5; done
else
    echo "==> Xcode CLT already installed."
fi

# ─── 2. Homebrew ───────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "==> Homebrew already installed."
fi

# ─── 3. Clone config repo ─────────────────────────────────────────────────
if [ ! -d "$NIX_CONFIG_DIR" ]; then
    echo "==> Cloning config repo..."
    mkdir -p "$HOME/.config"
    git clone https://github.com/smallstepman/smallstepman.github.io "$NIX_CONFIG_DIR"
else
    echo "==> Config repo already exists at $NIX_CONFIG_DIR"
fi

# ─── 4. Install Nix (Determinate installer) ───────────────────────────────
if ! command -v nix &>/dev/null; then
    echo "==> Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "==> Nix already installed."
fi

# ─── 5. Prepare external generated dataset ────────────────────────────────
echo "==> Preparing external generated dataset at $GENERATED_DIR..."
prepare_generated_dataset

# ─── 6. Apply nix-darwin config ────────────────────────────────────────────
echo "==> Building and applying nix-darwin configuration..."
cd "$NIX_CONFIG_DIR"

# shellcheck source=../scripts/external-input-flake.sh
. "$NIX_CONFIG_DIR/scripts/external-input-flake.sh"
WRAPPER=$(GENERATED_INPUT_DIR="$GENERATED_DIR" NIX_CONFIG_DIR="$NIX_CONFIG_DIR" mk_wrapper_flake)

NIXPKGS_ALLOW_UNFREE=1 nix build     --extra-experimental-features "nix-command flakes"     "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system"     --no-write-lock-file     --max-jobs 8 --cores 0

sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch     --flake "path:$WRAPPER#macbook-pro-m1"     --no-write-lock-file

echo ""
echo "Done! Open a new terminal to pick up all changes."
echo "Run 'vm bootstrap' to set up the NixOS VM."
