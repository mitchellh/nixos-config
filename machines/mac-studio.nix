{ config, lib, pkgs, ... }: {
  imports = [
    ./darwin-shared.nix
  ];

  # Set in Sept 2026 for the initial install.
  system.stateVersion = 6;

  # If the first switch complains about the nixbld gid, set this to
  # whatever the installer created:
  #   dscl . -read /Groups/nixbld PrimaryGroupID
  # ids.gids.nixbld = 30000;

  networking = {
    hostName = "mac-studio";
    localHostName = "mac-studio";
    computerName = "mac-studio";
  };

  # This is a headless home lab machine, so it should never sleep and
  # should always come back on its own.
  power = {
    sleep.computer = "never";
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
  };

  # Remote Login. Keys only; Tailscale SSH is the fallback.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  # Runs tailscaled as a launchd daemon so it's up before login. This
  # has to be authenticated once by hand: `sudo tailscale up --ssh`
  services.tailscale = {
    enable = true;
    overrideLocalDns = true;
  };
}
