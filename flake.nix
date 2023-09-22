{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Build a custom WSL installer
    nixos-wsl.url = github:nix-community/NixOS-WSL;
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other packages
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs: let
    mkDarwin = import ./lib/mkdarwin.nix;
    mkVM = import ./lib/mkvm.nix;

    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.neovim-nightly-overlay.overlay
      inputs.zig.overlays.default
    ];
  in {
    nixosConfigurations.vm-aarch64 = mkVM "vm-aarch64" {
      inherit nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "mitchellh";

      overlays = overlays ++ [(final: prev: {
        # Example of bringing in an unstable package:
        # open-vm-tools = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.open-vm-tools;
      })];
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

    darwinConfigurations.macbook-pro-m1 = mkDarwin "macbook-pro-m1" {
      inherit darwin nixpkgs home-manager overlays;
      system = "aarch64-darwin";
      user   = "mitchellh";
    };
  };
}
