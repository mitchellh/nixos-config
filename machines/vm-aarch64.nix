{ config, pkgs, lib, ... }: {
  imports = [
    ./hardware/vm-aarch64.nix
    ./hardware/disko-vm.nix
    ./vm-shared.nix
  ];

  # Setup qemu so we can run x86_64 binaries
  boot.binfmt.emulatedSystems = ["x86_64-linux"];

  # Let NetworkManager use DHCP on VMware NAT; VMware's DHCP reservation
  # keeps the guest pinned to 192.168.130.3 without breaking routing.
  networking.interfaces.enp2s0.useDHCP = true;

  # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;

  # This works through our custom module imported above
  virtualisation.vmware.guest.enable = true;

  # Share selected host directories
  fileSystems."/nixos-config" = {
    fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
    device = ".host:/nixos-config";
    options = [
      "umask=22"
      "uid=1000"
      "gid=1000"
      "allow_other"
      "auto_unmount"
      "defaults"
    ];
  };

  fileSystems."/Users/m/Projects" = {
    fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
    device = ".host:/Projects";
    options = [
      "umask=22"
      "uid=1000"
      "gid=1000"
      "allow_other"
      "auto_unmount"
      "defaults"
    ];
  };
}
