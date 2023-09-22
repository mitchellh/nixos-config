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

let
  # True if this is a WSL system.
  isWSL = nixos-wsl != null;

  # The config files for this system.
  machineConfig = ../machines/${name}.nix;
  userOSConfig = ../users/${user}/nixos.nix;
  userHMConfig = ../users/${user}/home-manager.nix;
in nixpkgs.lib.nixosSystem rec {
  inherit system;

  modules = [
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    { nixpkgs.overlays = overlays; }

    # Bring in WSL if this is a WSL build
    (if nixos-wsl != null then nixos-wsl.nixosModules.wsl else {})

    machineConfig
    userOSConfig
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user} = import userHMConfig {
        isWSL = isWSL;
      };
    }

    # We expose some extra arguments so that our modules can parameterize
    # better based on these values.
    {
      config._module.args = {
        currentSystem = system;
        currentSystemName = name;
        currentSystemUser = user;
        isWSL = isWSL;
      };
    }
  ];
}
