{ config, lib, pkgs, ... }: {
  imports = [
    ./darwin-shared.nix
    ./darwin-nushell.nix
  ];

  # Set in Nov 2026 for the initial install.
  system.stateVersion = 6;

  # If the first switch complains about the nixbld gid, set this to
  # whatever the installer created:
  #   dscl . -read /Groups/nixbld PrimaryGroupID
  # ids.gids.nixbld = 30000;

  networking = {
    hostName = "mac-mini";
    localHostName = "mac-mini";
    computerName = "mac-mini";
  };

  # Desktop apps. Shared apps are in users/mitchellh/darwin.nix.
  homebrew.casks = [
    "claude"
    "cleanshot"
    "discord"
    "fantastical"
    "google-chrome"
    "hammerspoon"
    "imageoptim"
    "istat-menus"
    "monodraw"
    "raycast"
    "rectangle"
    "screenflow"
    "slack"
    "spotify"
    "tailscale-app"
  ];
}
