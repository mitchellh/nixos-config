# den/aspects/features/wsl.nix
#
# WSL-specific system slice.
#
# Migrated from machines/wsl.nix (Task 10 of den migration).
# Note: wsl.defaultUser intentionally remains owned by den's built-in WSL
# provider, which already wires it from the declared host user.
{ den, lib, inputs, ... }: {
  den.aspects.wsl-system = {
    includes = [
      ({ host, ... }:
        lib.optionalAttrs (host.wsl.enable or false) {
          nixos = { pkgs, ... }: {
            imports = [
              inputs.nixos-wsl.nixosModules.wsl
            ];

            wsl.enable = true;
            wsl.wslConf.automount.root = "/mnt";
            wsl.startMenuLaunchers = true;

            nix.package = pkgs.nixVersions.latest;
            nix.extraOptions = ''
              keep-outputs = true
              keep-derivations = true
            '';
            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            system.stateVersion = "23.05";
          };
        })
    ];
  };
}
