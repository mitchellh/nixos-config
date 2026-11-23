{ config, lib, pkgs, ... }: {
  imports = [
    ./darwin-shared.nix
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

  # Nushell is the login shell on this machine. nix-darwin only changes
  # the shell of users it knows about, so mitchellh has to be a known
  # user (uid/gid match the account the macOS installer created).
  users.knownUsers = [ "mitchellh" ];
  users.users.mitchellh = {
    uid = 501;
    shell = lib.mkForce pkgs.nushell;
  };
  environment.shells = [ pkgs.nushell ];

  # As a login shell, Nushell starts without XDG_CONFIG_HOME and so reads
  # ~/Library/Application Support/nushell. Point that at the chezmoi
  # managed ~/.config/nushell. env.nu there imports the rest of the
  # environment from a fish login shell.
  home-manager.users.mitchellh = { config, ... }: {
    home.file."Library/Application Support/nushell".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/nushell";
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
