{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";

    # Locks nixpkgs to an older version with an older Kernel that boots
    # on VMware Fusion Tech Preview. This can be swapped to nixpkgs when
    # the TP fixes the bug.
    nixpkgs-old-kernel.url = "github:nixos/nixpkgs/bacbfd713b4781a4a82c1f390f8fe21ae3b8b95b";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-22.05";

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

      (final: prev: {
        # Zig doesn't export an overlay so we do it here
        zig-master = inputs.zig.packages.${prev.system}.master.latest;

        # Go we always want the latest version
        go = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.go_1_19;

        # To get Kitty 0.24.x. Delete this once it hits release.
        kitty = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.kitty;
      })
    ];
  in {
    nixosConfigurations.vm-aarch64 = mkVM "vm-aarch64" rec {
      inherit overlays home-manager;
      nixpkgs = inputs.nixpkgs-old-kernel;
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-aarch64-prl = mkVM "vm-aarch64-prl" rec {
      inherit overlays nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-aarch64-utm = mkVM "vm-aarch64-utm" rec {
      inherit overlays nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-intel = mkVM "vm-intel" rec {
      inherit nixpkgs home-manager overlays;
      system = "x86_64-linux";
      user   = "mitchellh";
    };
  };
}
