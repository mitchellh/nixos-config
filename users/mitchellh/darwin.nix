{ inputs, pkgs, ... }:

{
  # Apps every Mac gets. Machine-specific apps are in machines/*.nix.
  homebrew = {
    enable = true;
    casks  = [
      "1password"
    ];

    brews = [
      "gnupg"
    ];
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.mitchellh = {
    home = "/Users/mitchellh";
    shell = pkgs.fish;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "mitchellh";
}
