#!/bin/bash
# vm - NixOS VM management for VMware Fusion on macOS
# Usage: vm {help|bootstrap|switch|refresh-secrets|up|down|ip|ssh}
# Standalone: sh <(curl -sL https://smallstepman.github.io/vm.sh)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
NIXADDR="${NIXADDR:-192.168.130.3}"
VM_STATIC_MAC="${VM_STATIC_MAC:-00:0c:29:95:ec:2c}"
NIXPORT="${NIXPORT:-22}"
NIXUSER="${NIXUSER:-m}"
NIXINSTALLUSER="${NIXINSTALLUSER:-root}"
VM_SHARED_NIX_CONFIG_DIR="${VM_SHARED_NIX_CONFIG_DIR:-/nixos-config}"
NIXNAME="${NIXNAME:-vm-aarch64}"
NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix}"

SSH_OPTIONS="-o StrictHostKeyChecking=accept-new"
BOOTSTRAP_SSH_OPTIONS="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
INSTALL_SSH_PASSWORD="${INSTALL_SSH_PASSWORD:-root}"
export DISPLAY=

HOST_SSH_PUBKEY_FILE="${HOST_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
GENERATED_DIR="$NIX_CONFIG_DIR/machines/generated"

VM_BASE_DIR="$HOME/Virtual Machines.localized"
HOST_PROJECTS_DIR="${HOST_PROJECTS_DIR:-$HOME/Projects}"

# VMware Fusion download
VMWARE_FUSION_ARCHIVE_URL="https://ia803402.us.archive.org/16/items/vmwareworkstationarchive/Fusion/25H2"
VMWARE_FUSION_DMG="VMware-Fusion-25H2-24995814_universal.dmg"
# SHA256 of the DMG - update when changing VMWARE_FUSION_DMG
VMWARE_FUSION_SHA256="TODO_FILL_IN_AFTER_FIRST_VERIFIED_DOWNLOAD"

# NixOS ISO
NIXOS_ISO_URL="https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso"
NIXOS_ISO_SHA_URL="https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso.sha256"

# VMware Fusion paths
VMWARE_FUSION_APP="/Applications/VMware Fusion.app"
VMWARE_FUSION_LIB="$VMWARE_FUSION_APP/Contents/Library"
export PATH="$VMWARE_FUSION_LIB:$PATH"

VM_CPU_COUNT=7
VM_RAM_GB=32
VM_VRAM_GB=8
VM_DISK_GB=200


# Services script location varies by version
if [ -x "$VMWARE_FUSION_LIB/services/services.sh" ]; then
    VMWARE_SERVICES_SCRIPT="$VMWARE_FUSION_LIB/services/services.sh"
else
    VMWARE_SERVICES_SCRIPT="$VMWARE_FUSION_LIB/services.sh"
fi

VMNET8_DHCPD_CONF="/Library/Preferences/VMware Fusion/vmnet8/dhcpd.conf"

# ─── Remote shell snippets (executed on the VM via SSH) ─────────────────────

# The VM's DHCP-assigned static IP has no default route and DNS is unconfigured,
# so outbound connections (nix downloads, etc.) fail without this fixup.
REMOTE_FIX_INTERNET='ip route replace default via 192.168.130.2 dev enp2s0 || true;
if ! getent hosts channels.nixos.org >/dev/null 2>&1; then
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | sudo tee /etc/resolv.conf >/dev/null;
fi'

# Mount the VMware shared folder if not already mounted.
# On the NixOS ISO, vmhgfs-fuse lives in the nix profile after installing open-vm-tools.
# After a full NixOS install it's on the system PATH.
REMOTE_MOUNT_SHARED='sudo mkdir -p '"$VM_SHARED_NIX_CONFIG_DIR"';
if ! mountpoint -q '"$VM_SHARED_NIX_CONFIG_DIR"'; then
    if ! command -v vmhgfs-fuse >/dev/null 2>&1; then
        sudo nix --experimental-features "nix-command flakes" profile add nixpkgs#open-vm-tools >/dev/null;
    fi;
    sudo vmhgfs-fuse .host:/nixos-config '"$VM_SHARED_NIX_CONFIG_DIR"' -o uid=0,gid=0,allow_other,auto_unmount;
fi'

# ─── Helpers ────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

# Find the .vmx file for our NixOS VM
vm_find_vmx() {
    local vmx
    vmx=$(find "$VM_BASE_DIR" -name "NixOS*.vmx" -type f 2>/dev/null | head -1)
    if [ -z "$vmx" ]; then
        return 1
    fi
    echo "$vmx"
}

# Auto-detect VM IP via vmrun, fall back to static
vm_detect_ip() {
    local vmx
    vmx=$(vm_find_vmx 2>/dev/null) || true
    if [ -n "$vmx" ]; then
        local ip
        ip=$(vmrun -T fusion getGuestIPAddress "$vmx" 2>/dev/null) || true
        if [ -n "$ip" ]; then
            echo "$ip"
            return
        fi
    fi
    echo "$NIXADDR"
}

# ─── VMware Fusion Install ─────────────────────────────────────────────────

vm_ensure_vmware_fusion() {
    if [ -d "$VMWARE_FUSION_APP" ]; then
        echo "VMware Fusion already installed."
        return 0
    fi

    echo "VMware Fusion not found. Downloading..."
    local dmg_path="$HOME/Downloads/$VMWARE_FUSION_DMG"

    if [ ! -f "$dmg_path" ]; then
        curl -L -o "$dmg_path" "$VMWARE_FUSION_ARCHIVE_URL/$VMWARE_FUSION_DMG"
    fi

    # Verify SHA256
    local actual_sha
    actual_sha=$(shasum -a 256 "$dmg_path" | awk '{print $1}')
    if [ "$VMWARE_FUSION_SHA256" = "TODO_FILL_IN_AFTER_FIRST_VERIFIED_DOWNLOAD" ]; then
        echo "WARNING: No SHA256 configured for verification."
        echo "Downloaded DMG SHA256: $actual_sha"
        echo "Update VMWARE_FUSION_SHA256 in scripts/vm.sh with this value."
        read -rp "Continue with install? [y/N] " confirm
        [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || die "Aborted."
    elif [ "$actual_sha" != "$VMWARE_FUSION_SHA256" ]; then
        die "SHA256 mismatch!\n  Expected: $VMWARE_FUSION_SHA256\n  Got:      $actual_sha"
    fi

    echo "Mounting and installing VMware Fusion..."
    local mount_point
    mount_point=$(hdiutil attach "$dmg_path" -nobrowse | grep "/Volumes" | awk -F'\t' '{print $NF}')
    sudo cp -R "$mount_point/VMware Fusion.app" /Applications/
    hdiutil detach "$mount_point" -quiet
    echo "VMware Fusion installed successfully."

    # Re-detect services script
    if [ -x "$VMWARE_FUSION_LIB/services/services.sh" ]; then
        VMWARE_SERVICES_SCRIPT="$VMWARE_FUSION_LIB/services/services.sh"
    else
        VMWARE_SERVICES_SCRIPT="$VMWARE_FUSION_LIB/services.sh"
    fi
}

# ─── NixOS ISO ──────────────────────────────────────────────────────────────

vm_ensure_iso() {
    local existing_iso
    existing_iso=$(find "$VM_BASE_DIR" -name "nixos-minimal-*.iso" -type f 2>/dev/null | head -1)

    if [ -n "$existing_iso" ]; then
        echo "Found existing ISO: $existing_iso" >&2
        local remote_sha local_sha
        remote_sha=$(curl -sL "$NIXOS_ISO_SHA_URL" | awk '{print $1}')
        local_sha=$(shasum -a 256 "$existing_iso" | awk '{print $1}')
        if [ "$remote_sha" != "$local_sha" ]; then
            echo "ISO outdated, downloading latest..." >&2
            rm -f "$existing_iso"
        else
            echo "ISO is up to date." >&2
            echo "$existing_iso"
            return
        fi
    fi

    local filename
    filename=$(curl -sI "$NIXOS_ISO_URL" | grep -i location | sed 's/.*\///' | tr -d '\r')
    [ -z "$filename" ] && filename="nixos-minimal-25.11-latest-aarch64-linux.iso"
    echo "Downloading NixOS ISO: $filename" >&2
    curl -L -o "$VM_BASE_DIR/$filename" "$NIXOS_ISO_URL"
    echo "$VM_BASE_DIR/$filename"
}

# ─── DHCP Reservation ──────────────────────────────────────────────────────

vm_ensure_dhcp_reservation() {
    local dhcp_conf="$VMNET8_DHCPD_CONF"
    local host_name="NixOS-VM"

    if [ ! -f "$dhcp_conf" ]; then
        echo "Skipping DHCP reservation: $dhcp_conf not found"
        return
    fi

    local tmp_file
    tmp_file=$(mktemp)
    awk -v host_name="$host_name" '
        BEGIN { skipping = 0 }
        $1 == "host" && $2 == host_name { skipping = 1; next }
        skipping && $1 == "}" { skipping = 0; next }
        !skipping { print }
    ' "$dhcp_conf" > "$tmp_file"

    cat >>"$tmp_file" <<EOF

# Static DHCP reservation for NixOS VM
host ${host_name} {
    hardware ethernet ${VM_STATIC_MAC};
    fixed-address ${NIXADDR};
}
EOF

    echo "Configuring vmnet8 DHCP reservation (${VM_STATIC_MAC} -> ${NIXADDR})..."
    if sudo cp "$tmp_file" "$dhcp_conf"; then
        if [ -x "$VMWARE_SERVICES_SCRIPT" ]; then
            sudo "$VMWARE_SERVICES_SCRIPT" --stop 2>/dev/null || true
            sudo "$VMWARE_SERVICES_SCRIPT" --start 2>/dev/null || true
        fi
    fi
    rm -f "$tmp_file"
}

# ─── VM Create ──────────────────────────────────────────────────────────────

vm_create() {
    command -v vmrun >/dev/null 2>&1 || die "vmrun not found. Install VMware Fusion first."
    [ -d "$NIX_CONFIG_DIR" ] || die "Nix config dir not found: $NIX_CONFIG_DIR"
    mkdir -p "$HOST_PROJECTS_DIR"

    # If a VM already exists, start it if needed and return
    local existing_vmx
    existing_vmx=$(vm_find_vmx 2>/dev/null) || true
    if [ -n "$existing_vmx" ]; then
        echo "VM already exists: $existing_vmx"
        if ! vmrun list | grep -qF "$existing_vmx"; then
            echo "Starting existing VM..."
            vmrun start "$existing_vmx"
        else
            echo "VM is already running."
        fi
        echo "$existing_vmx"
        return 0
    fi

    local iso_file
    iso_file=$(vm_ensure_iso)

    # Extract version from ISO filename
    local nixos_version="25.11"
    if [[ "$iso_file" =~ nixos-minimal-([0-9]+\.[0-9]+)\. ]]; then
        nixos_version="${BASH_REMATCH[1]}"
    fi

    local vm_name="NixOS ${nixos_version} aarch64"
    local vm_dir="$VM_BASE_DIR/${vm_name}.vmwarevm"
    local vmx_file="$vm_dir/${vm_name}.vmx"

    echo ""
    echo "Creating VM: $vm_name"
    echo "ISO: $iso_file"

    mkdir -p "$vm_dir"

    cat >"$vmx_file" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "22"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvram = "${vm_name}.nvram"
virtualHW.productCompatibility = "hosted"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
displayName = "${vm_name}"
firmware = "efi"
guestOS = "arm-other6xlinux-64"
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
sound.autoDetect = "TRUE"
sound.virtualDev = "hdaudio"
sound.fileName = "-1"
sound.present = "TRUE"
numvcpus = "${VM_CPU_COUNT}"
cpuid.coresPerSocket = "${VM_CPU_COUNT}"
# must be experssed as MB, so we need to convert from GB
memsize = "$((VM_RAM_GB * 1024))"
sata0.present = "TRUE"
nvme0.present = "TRUE"
nvme0:0.fileName = "Virtual Disk.vmdk"
nvme0:0.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "${iso_file}"
sata0:1.present = "TRUE"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
ethernet0.addressType = "static"
ethernet0.address = "${VM_STATIC_MAC}"
ethernet0.virtualDev = "e1000e"
ethernet0.linkStatePropagation.enable = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.vnet = "vmnet8"
ethernet0.startConnected = "TRUE"
ethernet0.present = "TRUE"
extendedConfigFile = "${vm_name}.vmxf"
isolation.tools.hgfs.disable = "FALSE"
hgfs.mapRootShare = "TRUE"
hgfs.linkRootShare = "TRUE"
sharedFolder0.present = "TRUE"
sharedFolder0.enabled = "TRUE"
sharedFolder0.readAccess = "TRUE"
sharedFolder0.writeAccess = "TRUE"
sharedFolder0.hostPath = "$NIX_CONFIG_DIR"
sharedFolder0.guestName = "nixos-config"
sharedFolder0.expiration = "never"
sharedFolder1.present = "TRUE"
sharedFolder1.enabled = "TRUE"
sharedFolder1.readAccess = "TRUE"
sharedFolder1.writeAccess = "TRUE"
sharedFolder1.hostPath = "$HOST_PROJECTS_DIR"
sharedFolder1.guestName = "Projects"
sharedFolder1.expiration = "never"
sharedFolder.maxNum = "2"
floppy0.present = "FALSE"
mks.enable3d = "TRUE"
svga.graphicsMemoryKB = "$((VM_VRAM_GB * 1024 * 1024))"
gui.fitGuestUsingNativeDisplayResolution = "TRUE"
vmxstats.filename = "${vm_name}.scoreboard"
svga.vramSize = "$((256 * 1024 * 1024))"
EOF

    touch "$vm_dir/${vm_name}.nvram"
    echo '<?xml version="1.0"?><Foundry><VM><VMId type="string">'"$(uuidgen)"'</VMId></VM></Foundry>' >"$vm_dir/${vm_name}.vmxf"
    touch "$vm_dir/${vm_name}.scoreboard"

    echo "Creating virtual disk..."
    if [ -f "$VMWARE_FUSION_LIB/vmware-vdiskmanager" ]; then
        "$VMWARE_FUSION_LIB/vmware-vdiskmanager" -c -s "${VM_DISK_GB}GB" -a nvme -t 0 "$vm_dir/Virtual Disk.vmdk"
    elif command -v vmware-vdiskmanager >/dev/null 2>&1; then
        vmware-vdiskmanager -c -s "${VM_DISK_GB}GB" -a nvme -t 0 "$vm_dir/Virtual Disk.vmdk"
    else
        die "vmware-vdiskmanager not found."
    fi

    vm_ensure_dhcp_reservation

    echo ""
    echo "VM created: $vm_name"
    echo "  Location: $vm_dir"
    echo "  CPU: $VM_CPU_COUNT cores | RAM: ${VM_RAM_GB}GB | VRAM: ${VM_VRAM_GB}GB | Disk: ${VM_DISK_GB}GB"
    echo "  Network: NAT (vmnet8) | Static IP: $NIXADDR"

    vmrun start "$vmx_file"
    echo "$vmx_file"
}

# ─── Wait for SSH ───────────────────────────────────────────────────────────

vm_wait_for_ssh() {
    echo ""
    echo "Waiting for SSH access to root@${NIXADDR}..."
    echo ">> In the VM console, run: sudo su; passwd  (set password to 'root')"
    echo ""
    while true; do
        if sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "echo ok" >/dev/null 2>&1; then
            echo "SSH connection established!"
            return 0
        fi
        sleep 5
    done
}

# ─── Prepare Host Auth Keys ────────────────────────────────────────────────

vm_prepare_host_authorized_keys() {
    [ -f "$HOST_SSH_PUBKEY_FILE" ] || die "SSH public key not found: $HOST_SSH_PUBKEY_FILE"
    mkdir -p "$GENERATED_DIR"
    # host-authorized-keys  → authorizes the macOS host key on the VM (nixos.nix)
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/host-authorized-keys"
    # mac-host-authorized-keys → authorizes the VM's use of the same key on the
    # macOS host sshd (darwin.nix), enabling Docker-over-SSH from the VM.
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/mac-host-authorized-keys"
}

# ─── Prepare SOPS Age Key ──────────────────────────────────────────────────

vm_prepare_sops_age_key() {
    mkdir -p "$GENERATED_DIR"
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "$REMOTE_FIX_INTERNET"' &&
        sudo mkdir -p /var/lib/sops-nix
        sudo chmod 700 /var/lib/sops-nix
        if [ ! -f /var/lib/sops-nix/key.txt ]; then
            sudo nix-shell -p age --run "age-keygen -o /var/lib/sops-nix/key.txt"
            sudo chmod 600 /var/lib/sops-nix/key.txt
        fi
        sudo nix-shell -p age --run "age-keygen -y /var/lib/sops-nix/key.txt"
    ' | tr -d '\r' > "$GENERATED_DIR/vm-age-pubkey"

    if ! grep -q '^age1' "$GENERATED_DIR/vm-age-pubkey"; then
        die "Failed to fetch VM sops age public key"
    fi
}

# ─── Collect Secrets ────────────────────────────────────────────────────────

vm_collect_secrets() {
    touch "$NIX_CONFIG_DIR/machines/secrets.yaml"
    git -C "$NIX_CONFIG_DIR" add -f machines/secrets.yaml
    (cd "$NIX_CONFIG_DIR" && nix --extra-experimental-features 'nix-command flakes' run "$NIX_CONFIG_DIR#collect-secrets")
    git -C "$NIX_CONFIG_DIR" reset -q -- machines/secrets.yaml
}

# ─── VM Install ─────────────────────────────────────────────────────────────

vm_install() {
    vm_prepare_host_authorized_keys
    vm_prepare_sops_age_key
    git -C "$NIX_CONFIG_DIR" add machines/generated/vm-age-pubkey machines/generated/host-authorized-keys machines/generated/mac-host-authorized-keys
    vm_collect_secrets

    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "$REMOTE_FIX_INTERNET && $REMOTE_MOUNT_SHARED"' &&
        if [ ! -f '"$VM_SHARED_NIX_CONFIG_DIR"'/flake.nix ]; then
            echo "Error: flake.nix not found in '"$VM_SHARED_NIX_CONFIG_DIR"'"
            exit 1
        fi &&
        cd '"$VM_SHARED_NIX_CONFIG_DIR"' &&
        sudo nix --experimental-features "nix-command flakes" run \
            github:nix-community/disko -- \
            --mode disko \
            '"$VM_SHARED_NIX_CONFIG_DIR"'/machines/hardware/disko-vm.nix &&
        sudo mkdir -p /mnt/var/lib/sops-nix &&
        sudo cp /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt &&
        sudo chmod 700 /mnt/var/lib/sops-nix &&
        sudo chmod 600 /mnt/var/lib/sops-nix/key.txt &&
        NIXCFG_CLEAN=/tmp/nixos-config-clean &&
        rm -rf "$NIXCFG_CLEAN" &&
        mkdir -p "$NIXCFG_CLEAN" &&
        tar -C '"$VM_SHARED_NIX_CONFIG_DIR"' --exclude="*.sock" -cf - . | tar -C "$NIXCFG_CLEAN" -xf - &&
        sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-install \
            --flake "path:$NIXCFG_CLEAN#'"$NIXNAME"'" \
            --no-root-passwd &&
        reboot
    '
}

# ─── Commands ───────────────────────────────────────────────────────────────

cmd_help() {
    cat <<'EOF'
vm - NixOS VM management for VMware Fusion

Usage: vm <command>

Commands:
  help              Show this help
  bootstrap [--redo] Full setup: install VMware Fusion, create VM, wait for
                    SSH, install NixOS. --redo destroys existing VM first
  switch            Run nixos-rebuild switch on the VM via shared folder
  refresh-secrets   Regenerate sops keys and re-encrypt secrets
  up                Start the VM
  down              Stop the VM (graceful shutdown)
  ip                Print the VM's IP address
  ssh [cmd]         SSH into the VM, or run a command over SSH
EOF
}

cmd_up() {
    local vmx
    vmx=$(vm_find_vmx) || die "No VM found. Run 'vm bootstrap' first."
    if vmrun list | grep -qF "$vmx"; then
        echo "VM is already running."
    else
        echo "Starting VM..."
        vmrun start "$vmx"
    fi
}

cmd_down() {
    local vmx
    vmx=$(vm_find_vmx) || die "No VM found."
    if vmrun list | grep -qF "$vmx"; then
        echo "Stopping VM..."
        vmrun stop "$vmx" soft
    else
        echo "VM is not running."
    fi
}

cmd_ip() {
    vm_detect_ip
}

cmd_ssh() {
    local addr
    addr=$(vm_detect_ip)
    if [ $# -gt 0 ]; then
        ssh $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}" "$@"
    else
        ssh $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}"
    fi
}

vm_destroy() {
    local vmx
    vmx=$(vm_find_vmx 2>/dev/null) || true
    if [ -z "$vmx" ]; then
        echo "No VM found."
        return 0
    fi
    if vmrun list | grep -qF "$vmx"; then
        echo "Stopping VM..."
        vmrun stop "$vmx" hard 2>/dev/null || true
    fi
    local vm_dir
    vm_dir=$(dirname "$vmx")
    echo "Deleting $vm_dir ..."
    rm -rf "$vm_dir"
}

cmd_bootstrap() {
    if [ "${1:-}" = "--redo" ]; then
        echo "==> Destroying existing VM..."
        vm_destroy
    fi

    echo "==> Ensuring VMware Fusion is installed..."
    vm_ensure_vmware_fusion

    echo ""
    echo "==> Creating NixOS VM..."
    vm_create

    echo ""
    echo "==> Waiting for SSH (set root password in VM console)..."
    vm_wait_for_ssh

    echo ""
    echo "==> Installing NixOS..."
    vm_install

    echo ""
    echo "Bootstrap complete! The VM will reboot into NixOS."
    echo "After reboot, use 'vm switch' to apply configuration changes."
}

cmd_switch() {
    local addr
    addr=$(vm_detect_ip)
    echo "Switching NixOS config on VM at $addr..."

    ssh -t $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}" "$REMOTE_MOUNT_SHARED"' &&
        sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake "path:'"$VM_SHARED_NIX_CONFIG_DIR"'#'"$NIXNAME"'"
    '
}

cmd_refresh_secrets() {
    local addr
    addr=$(vm_detect_ip)
    echo "Refreshing secrets for VM at $addr..."

    # Get VM age public key (uses normal SSH, not bootstrap)
    mkdir -p "$GENERATED_DIR"
    ssh $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}" "
        sudo mkdir -p /var/lib/sops-nix &&
        sudo chmod 700 /var/lib/sops-nix &&
        if [ ! -f /var/lib/sops-nix/key.txt ]; then
            sudo nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt'
            sudo chmod 600 /var/lib/sops-nix/key.txt
        fi &&
        sudo nix-shell -p age --run 'age-keygen -y /var/lib/sops-nix/key.txt'
    " | tr -d '\r' > "$GENERATED_DIR/vm-age-pubkey"

    if ! grep -q '^age1' "$GENERATED_DIR/vm-age-pubkey"; then
        die "Failed to fetch VM sops age public key"
    fi

    vm_prepare_host_authorized_keys
    git -C "$NIX_CONFIG_DIR" add machines/generated/vm-age-pubkey machines/generated/host-authorized-keys machines/generated/mac-host-authorized-keys
    vm_collect_secrets
    echo "Secrets refreshed. Run 'vm switch' to apply."
}

# ─── Standalone install ─────────────────────────────────────────────────────
# When invoked with no args (e.g. via curl pipe), install self and bootstrap.

cmd_standalone_install() {
    local dest="$HOME/vm.sh"
    local self
    self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

    # If run from the cloned repo, symlink; otherwise we're a temp download, copy
    if [ -d "$NIX_CONFIG_DIR/docs" ] && [ "$self" = "$NIX_CONFIG_DIR/docs/vm.sh" ]; then
        ln -sf "$self" "$dest" 2>/dev/null || cp "$self" "$dest"
    else
        cp "$self" "$dest"
    fi
    chmod +x "$dest"
    echo "Installed: $dest"
    echo "Usage: ~/vm.sh {help|bootstrap|switch|refresh-secrets|up|down|ip|ssh}"

    if vm_find_vmx >/dev/null 2>&1; then
        echo ""
        echo "Existing NixOS VM found. Run '~/vm.sh switch' to apply config changes."
    else
        echo ""
        echo "No NixOS VM found. Starting bootstrap..."
        cmd_bootstrap
    fi
}

# ─── Main ───────────────────────────────────────────────────────────────────

# No args: standalone install mode (for curl pipe usage)
if [ $# -eq 0 ]; then
    cmd_standalone_install
    exit 0
fi

cmd="$1"
shift

case "$cmd" in
    help)              cmd_help ;;
    bootstrap)         cmd_bootstrap "$@" ;;
    switch)            cmd_switch ;;
    refresh-secrets)   cmd_refresh_secrets ;;
    up)                cmd_up ;;
    down)              cmd_down ;;
    ip)                cmd_ip ;;
    ssh)               cmd_ssh "$@" ;;
    *)                 echo "Unknown command: $cmd"; cmd_help; exit 1 ;;
esac
