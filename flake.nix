{
  description = "NixOS systems and tools by zerodeth";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/release-21.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-21.11";

      # We want home-manager to use the same set of nixpkgs as our system.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other packages
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    zig.url = "github:arqv/zig-overlay";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
    mkVM = import ./lib/mkvm.nix;

    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.neovim-nightly-overlay.overlay

      # Zig doesn't export an overlay so we do it here
      (final: prev: {
        zig-master = inputs.zig.packages.${prev.system}.master.latest;
      })
    ];
  in {
    nixosConfigurations.vm-aarch64 = mkVM "vm-aarch64" rec {
      inherit overlays nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "zerodeth";
    };

    nixosConfigurations.vm-intel = mkVM "vm-intel" rec {
      inherit nixpkgs home-manager overlays;
      system = "x86_64-linux";
      user   = "zerodeth";
    };
  };
}
