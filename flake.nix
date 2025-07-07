{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Used to get ibus 1.5.29 which has some quirks we want to test.
    nixpkgs-old-ibus.url = "github:nixos/nixpkgs/e2dd4e18cc1c7314e24154331bae07df76eb582f";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Master nixpkgs is used for really bleeding edge packages. Warning
    # that this is extremely unstable and shouldn't be relied on. Its
    # mostly for testing.
    nixpkgs-master.url = "github:nixos/nixpkgs";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      # We need to use nightly home-manager because it contains this
      # fix we need for nushell nightly:
      # https://github.com/nix-community/home-manager/commit/a69ebd97025969679de9f930958accbe39b4c705
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
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
    nvim-codecompanion.url = "github:olimorris/codecompanion.nvim";
    nvim-codecompanion.flake = false;
    nvim-conform.url = "github:stevearc/conform.nvim/v9.0.0";
    nvim-conform.flake = false;
    nvim-dressing.url = "github:stevearc/dressing.nvim";
    nvim-dressing.flake = false;
    nvim-gitsigns.url = "github:lewis6991/gitsigns.nvim/v1.0.2";
    nvim-gitsigns.flake = false;
    nvim-lspconfig.url = "github:neovim/nvim-lspconfig";
    nvim-lspconfig.flake = false;
    nvim-lualine.url ="github:nvim-lualine/lualine.nvim";
    nvim-lualine.flake = false;
    nvim-nui.url = "github:MunifTanjim/nui.nvim";
    nvim-nui.flake = false;
    nvim-plenary.url = "github:nvim-lua/plenary.nvim";
    nvim-plenary.flake = false;
    nvim-render-markdown.url = "github:MeanderingProgrammer/render-markdown.nvim";
    nvim-render-markdown.flake = false;
    nvim-telescope.url = "github:nvim-telescope/telescope.nvim/0.1.8";
    nvim-telescope.flake = false;
    nvim-treesitter-context.url = "github:nvim-treesitter/nvim-treesitter-context";
    nvim-treesitter-context.flake = false;
    nvim-web-devicons.url = "github:nvim-tree/nvim-web-devicons";
    nvim-web-devicons.flake = false;
    vim-copilot.url = "github:github/copilot.vim/v1.48.0";
    vim-copilot.flake = false;
    vim-misc.url = "github:mitchellh/vim-misc";
    vim-misc.flake = false;
  };

  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.jujutsu.overlays.default
      inputs.zig.overlays.default

      (final: prev:
        let
          # We need to create a new nixpkgs instance from the unstable input
          # so that we can apply configuration to it, such as allowing unfree
          # packages.
          nixpkgs-unstable-configured = import inputs.nixpkgs-unstable {
            system = prev.system;
            config.allowUnfree = true;
          };
        in
        rec {
          # gh CLI on stable has bugs.
          gh = nixpkgs-unstable-configured.gh;

          # Want the latest version of these
          claude-code = nixpkgs-unstable-configured.claude-code;
          nushell = nixpkgs-unstable-configured.nushell;

          ibus = ibus_stable;
          ibus_stable = inputs.nixpkgs.legacyPackages.${prev.system}.ibus;
          ibus_1_5_29 = inputs.nixpkgs-old-ibus.legacyPackages.${prev.system}.ibus;
          ibus_1_5_31 = nixpkgs-unstable-configured.ibus;
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

    nixosConfigurations.vm-aarch64-prl = mkSystem "vm-aarch64-prl" rec {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" rec {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-intel = mkSystem "vm-intel" rec {
      system = "x86_64-linux";
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
