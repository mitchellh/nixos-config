{ pkgs, ... }:

{
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix)
  ];

  homebrew.enable = true;

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.mitchellh = {
    home = "/Users/mitchellh";
    shell = pkgs.fish;
  };
}
