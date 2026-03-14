{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.default = {
    includes = [ den._.wsl ];

    nixos = {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
    };

    darwin = {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
    };
  };

  # Home Manager host-level options belong on hm-host so the documented HM
  # integration context owns the OS-side wiring.
  den.ctx.hm-host.includes = [
    ({ host, ... }:
      let
        systemModule = { ... }: {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
        };
      in
      (lib.optionalAttrs (host.class == "nixos") {
        nixos = systemModule;
      }) // (lib.optionalAttrs (host.class == "darwin") {
        darwin = systemModule;
      }))
  ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };
}
