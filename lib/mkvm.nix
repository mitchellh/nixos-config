# This function creates a NixOS system based on our VM setup for a
# particular architecture.
{ nixpkgs, home-manager, system, user }:

nixpkgs.lib.nixosSystem rec {
  inherit system;

  modules = [
    ../hardware/vm.nix
    ../machines/vm.nix
    ../machines/vm-arch/${system}.nix
    ../users/${user}/nixos.nix
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user} = import ../users/${user}/home-manager.nix;
    }
  ];

  extraArgs = {
    currentSystem = system;
  };
}
