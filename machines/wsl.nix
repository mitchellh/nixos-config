{ pkgs, currentSystemUser, ... }: {
  imports = [];

  wsl = {
    enable = true;
    wslConf.automount.root = "/mnt";
    defaultUser = currentSystemUser;
    startMenuLaunchers = true;
  };

  # NixOS-WSL manages /etc/resolv.conf directly.
  networking.resolvconf.enable = false;

  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';
  };

  system.stateVersion = "23.05";
}
