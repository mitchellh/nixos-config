{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.default = {
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

  den.schema.host = { lib, ... }: {
    options.profile = lib.mkOption {
      type = lib.types.str;
      description = "Host configuration profile name, used to select the NixOS configuration for this host.";
      example = "vm";
    };
    options.vmware.enable = lib.mkEnableOption "VMware-specific host behavior";
    options.graphical.enable = lib.mkEnableOption "Graphical desktop behavior";
  };
}
