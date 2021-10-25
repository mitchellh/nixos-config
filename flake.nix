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
  };

  outputs = { self, nixpkgs, home-manager }: let
    mkVM = import ./lib/mkvm.nix;
  in {
    nixosConfigurations.vm-aarch64 = mkVM {
      inherit nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-intel = mkVM {
      inherit nixpkgs home-manager;
      system = "x86_64-linux";
      user   = "mitchellh";
    };
  };
}
