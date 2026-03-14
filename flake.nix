{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

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
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other packages
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri - scrollable-tiling Wayland compositor
    niri.url = "github:sodiboo/niri-flake";
    niri-scratchpad.url = "github:argosnothing/niri-scratchpad-rs";
    # niri-deep = {
    #   url = "/Users/m/Projects/niri-deep";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # LLM agents for Nix
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Python/uv packaging toolchain (used for APM and other uv-based Python tools)
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LazyVim Nix (declarative Neovim + LazyVim)
    lazyvim.url = "github:pfassina/lazyvim-nix";

    # Non-flake sources for packages we build ourselves
    agent-of-empires-src.url = "github:njbrake/agent-of-empires";
    uniclip-src = { url = "github:quackduck/uniclip"; flake = false; };
    tmux-menus-src = { url = "github:jaclu/tmux-menus"; flake = false; };
    aw-import-screentime-src = { url = "github:ActivityWatch/aw-import-screentime/8d6bf4a84bac840c8af577652ee70514ef3e6bc1"; flake = false; };

    # Mango window control for Wayland
    mangowc = {
      url = "github:DreamMaoMao/mangowc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia shell for Wayland
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative git repo management
    git-repo-manager = {
      url = "github:hakoerber/git-repo-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sopsidy = {
      url = "github:timewave-computer/sopsidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Doom Emacs via nix-doom-emacs-unstraightened (builds Doom + deps with Nix)
    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      # Don't pull in its nixpkgs — neither the module nor overlay uses it
      inputs.nixpkgs.follows = "";
    };

    # Gastown - multi-agent orchestration system for Claude Code
    gastown = {
      url = "github:steveyegge/gastown";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # import-tree - import Nix modules by directory tree (required by den)
    import-tree.url = "github:vic/import-tree";

  };

  # Den - aspect-oriented context-driven Nix configurations (top-level dotted path
  # so that `inputs.den.url = "github:vic/den";` is unambiguous in this file)
  inputs.den.url = "github:vic/den";

  # flake-aspects must be a direct input here because den's lib.nix accesses
  # inputs.flake-aspects.lib from the consumer flake's inputs, not den's own.
  inputs.flake-aspects.url = "github:vic/flake-aspects";

  outputs = { self, nixpkgs, ... }@inputs: {
    lib.mkOutputs = { generated, yeetAndYoink ? null }:
      import ./den/mk-config-outputs.nix {
        inputs = inputs // { inherit generated yeetAndYoink; };
      };
  };
}
