# This function creates a NixOS system based on our VM setup for a
# particular architecture.
name: {
  nixpkgs,
  home-manager,
  nixos-wsl ? null,
  system,
  user,
  overlays,
}:

nixpkgs.lib.nixosSystem rec {
  inherit system;

  modules = [
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    { nixpkgs.overlays = overlays; }

    # Bring in WSL if this is a WSL build
    (if nixos-wsl != null then nixos-wsl.nixosModules.wsl else {})

    ../machines/${name}.nix
    ../users/${user}/nixos.nix
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user} = import ../users/${user}/home-manager.nix;
    }

    # We expose some extra arguments so that our modules can parameterize
    # better based on these values.
    {
      config._module.args = {
        currentSystem = system;
        currentSystemName = name;
        currentSystemUser = user;
      };
    }
  ];
}
