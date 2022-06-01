{ config, pkgs, lib, modulesPath, ... }: {
  imports = [
    # Parallels is qemu under the covers. This brings in important kernel
    # modules to get a lot of the stuff working.
    (modulesPath + "/profiles/qemu-guest.nix")

    ../modules/parallels-guest.nix
    ./vm-shared.nix
  ];

  # An earlier kernel is required for now since the parallels-guest
  # patches don't work yet with 5.18. I have a link to a working patch
  # but going to put that in a separate commit.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_5_17;

  # The official parallels guest support does not work currently.
  # https://github.com/NixOS/nixpkgs/pull/153665
  disabledModules = [ "virtualisation/parallels-guest.nix" ];
  hardware.parallels = {
    enable = true;
    package = (config.boot.kernelPackages.callPackage ../pkgs/parallels-tools/default.nix { });
  };

  # Interface is this on my M1
  networking.interfaces.enp0s5.useDHCP = true;

  # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
