{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/release-21.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-21.05";

      # We want home-manager to use the same set of nixpkgs as our system.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For our aarch64 VM, we use different versions since there are some
    # changes that are required for aarch64 to build in reliably.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager-unstable = {
      url = "github:nix-community/home-manager/release-21.05";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, home-manager-unstable }: let
    mkVM = import ./lib/mkvm.nix;
  in {
    nixosConfigurations.vm-aarch64 = mkVM "vm-aarch64" {
      nixpkgs = nixpkgs-unstable;
      home-manager = home-manager-unstable;
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-intel = mkVM "vm-intel" {
      inherit nixpkgs home-manager;
      system = "x86_64-linux";
      user   = "mitchellh";
    };
  };
}
