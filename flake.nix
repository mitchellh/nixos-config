{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # Used to get ibus 1.5.29 which has some quirks we want to test.
    nixpkgs-old-ibus.url = "github:nixos/nixpkgs/e2dd4e18cc1c7314e24154331bae07df76eb582f";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    # https://github.com/cpick/nix-rosetta-builder
    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      # We need to use nightly home-manager because it contains this
      # fix we need for nushell nightly:
      # https://github.com/nix-community/home-manager/commit/a69ebd97025969679de9f930958accbe39b4c705
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };

    # Other packages
    jujutsu.url = "github:martinvonz/jj";
    zig.url = "github:mitchellh/zig-overlay";

    # Non-flakes
    theme-bobthefish.url = "github:oh-my-fish/theme-bobthefish/e3b4d4eafc23516e35f162686f08a42edf844e40";
    theme-bobthefish.flake = false;
    fish-fzf.url = "github:jethrokuan/fzf/24f4739fc1dffafcc0da3ccfbbd14d9c7d31827a";
    fish-fzf.flake = false;
    fish-foreign-env.url = "github:oh-my-fish/plugin-foreign-env/dddd9213272a0ab848d474d0cbde12ad034e65bc";
    fish-foreign-env.flake = false;
  };

  outputs = { nixpkgs, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.jujutsu.overlays.default
      inputs.zig.overlays.default

      (_final: prev: let
        system = prev.stdenv.hostPlatform.system;
        unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        # gh CLI on stable has bugs.
        gh = unstable.gh;

        # Want the latest version of these
        claude-code = unstable.claude-code;
        nushell = unstable.nushell;

        ibus = prev.ibus;
        ibus_stable = prev.ibus;
        ibus_1_5_29 = inputs.nixpkgs-old-ibus.legacyPackages.${system}.ibus;
        ibus_1_5_31 = unstable.ibus;
      })
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "mitchellh";
      wsl    = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
      system = "aarch64-darwin";
      user   = "mitchellh";
      darwin = true;
    };
  };
}
