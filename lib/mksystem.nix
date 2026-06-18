# This function creates a NixOS system based on our VM setup for a
# particular architecture.
{ nixpkgs, overlays, inputs }:

name:
{
  system,
  user,
  darwin ? false,
  wsl ? false
}:

let
  # True if this is a WSL system.
  isWSL = wsl;

  # True if Linux, which is a heuristic for not being Darwin.
  isLinux = !darwin && !isWSL;

  # The config files for this system.
  machineConfig = ../machines/${name}.nix;
  userOSConfig = ../users/${user}/${if darwin then "darwin" else "nixos" }.nix;
  userHMConfig = ../users/${user}/home-manager.nix;

  # NixOS vs nix-darwin functionst
  systemFunc = if darwin then inputs.darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
  home-manager = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;

  inherit (nixpkgs.lib) optionals;
in systemFunc rec {
  inherit system;

  modules = [
    # Apply our overlays. Overlays are keyed by system type so we have
    # to go through and apply our system type. We do this first so
    # the overlays are available globally.
    { nixpkgs.overlays = overlays; }

    # Allow unfree packages.
    { nixpkgs.config.allowUnfree = true; }
  ] ++ optionals isWSL [
    inputs.nixos-wsl.nixosModules.wsl
  ] ++ optionals isLinux [
    inputs.nix-snapd.nixosModules.default
  ] ++ optionals darwin [
    # An existing Linux builder is needed to initially bootstrap
    # `nix-rosetta-builder`. After the first `darwin-rebuild switch`,
    # `nix-rosetta-builder` can rebuild itself.
    inputs.nix-rosetta-builder.darwinModules.default
    {
      # see available options in module.nix's `options.nix-rosetta-builder`
      nix-rosetta-builder.onDemand = true;

      # The cache.nixos.org substitute for openapv 0.2.1.2 has a NAR hash
      # mismatch. Force this one package to build from source in the builder
      # image instead of making every Linux dependency skip the cache.
      # Try to remove this whenever we update nixpkgs.
      nix-rosetta-builder.potentiallyInsecureExtraNixosModule = {
        nixpkgs.overlays = [
          (_final: prev: {
            openapv = prev.openapv.overrideAttrs (_old: {
              allowSubstitutes = false;
              preferLocalBuild = true;
            });
          })
        ];
      };

      # `nix-rosetta-builder` depends on `lima`, which is currently
      # marked insecure in nixpkgs.
      nixpkgs.config.permittedInsecurePackages = [ "lima-1.2.2" ];
    }
  ] ++ [
    machineConfig
    userOSConfig
    home-manager.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${user} = import userHMConfig {
        isWSL = isWSL;
        inputs = inputs;
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
        inputs = inputs;
      };
    }
  ];
}
