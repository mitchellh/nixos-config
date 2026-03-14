# den/aspects/hosts/vm-aarch64.nix
#
# Host aspect for the vm-aarch64 (vm-macbook) NixOS machine.
#
# Wires den-native feature aspects (linux-core, secrets) and owns the
# host-specific remnants that do not belong in any reusable feature aspect:
#   - Hostname provisioning
#   - Host age pubkey for sops secret collection
#   - aarch64-specific x86_64 binfmt emulation
#   - DHCP pinning for the VMware NAT NIC (enp2s0)
#   - 127.0.0.1 hosts entry for vm-macbook
#   - openwebui-local-proxy systemd service
#   - users.users.m host-specific settings (extraGroups, authorizedKeys)
{ den, generated, inputs, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      # Core Linux system behavior (non-desktop, non-WSL-specific).
      den.aspects.linux-core

      # Secret-backed system settings (sops, Tailscale, user password, rbw).
      den.aspects.secrets

      # Linux graphical desktop stack (niri, greetd, keyd, kitty, etc.).
      den.aspects.linux-desktop

      # VMware guest integration (vmware tools, HGFS mounts, niri bindings).
      den.aspects.vmware

      # Hostname battery: sets networking.hostName from den.hosts config.
      den.provides.hostname

      # Host-specific NixOS configuration that does not belong in a shared aspect.
        ({ host, ... }: {
          nixos = { config, pkgs, lib, ... }: {
            imports = [
              inputs.disko.nixosModules.disko
            ];

            # Copied from the old nixos-generate-config output so the VM keeps the
            # same initrd driver set after the legacy hardware file removal.
            boot.initrd.availableKernelModules = [ "uhci_hcd" "ahci" "xhci_pci" "nvme" "usbhid" "sr_mod" ];
            boot.initrd.kernelModules = [ ];
            boot.kernelModules = [ ];
            boot.extraModulePackages = [ ];
            swapDevices = [ ];

            # Copied from the former disko file so the VM disk layout remains
            # den-owned while still producing the same /boot and / filesystem setup.
            disko.devices = {
              disk.main = {
                device = lib.mkDefault "/dev/nvme0n1";
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    ESP = {
                      size = "500M";
                      type = "EF00";
                      content = {
                        type = "filesystem";
                        format = "vfat";
                        mountpoint = "/boot";
                        mountOptions = [ "umask=0077" ];
                      };
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/";
                      };
                    };
                  };
                };
              };
            };

            # Setup qemu so this aarch64 VM can run x86_64 binaries.
            boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

            # Let NetworkManager use DHCP on VMware NAT; VMware's DHCP reservation
            # keeps this guest pinned to 192.168.130.3.
            networking.interfaces.enp2s0.useDHCP = true;

            # Host-specific sops age public key used by secret collection.
            sops.hostPubKey = lib.removeSuffix "\n"
              (generated.readFile "vm-age-pubkey");

            # Ensure vm-macbook resolves locally regardless of DNS state.
            networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];

            # Expose a tunneled Open WebUI instance on localhost:80.
            systemd.services.openwebui-local-proxy = {
              description = "Expose tunneled Open WebUI on localhost:80";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
                Restart = "always";
                RestartSec = 1;
              };
            };

            # User m: host-specific group membership and SSH authorized keys.
            # Note: wheel and networkmanager are already added by den.provides.primary-user;
            # only add the vm-aarch64-specific lxd group here to avoid duplicates.
            users.users.m = {
              extraGroups = [ "lxd" ];
              openssh.authorizedKeys.keyFiles = [
                (generated.requireFile "host-authorized-keys")
              ];
            };
          };
        })
    ];
  };
}
