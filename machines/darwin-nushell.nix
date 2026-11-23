# Makes Nushell the login shell. Import this from a machine's config.
{ config, lib, pkgs, ... }: {
  # nix-darwin only changes the shell of users it knows about, so
  # mitchellh has to be a known user. The uid/gid match the account the
  # macOS installer creates for the first user.
  users.knownUsers = [ "mitchellh" ];
  users.users.mitchellh = {
    uid = 501;
    shell = lib.mkForce pkgs.nushell;
  };
  environment.shells = lib.mkAfter [ pkgs.nushell ];

  # As a login shell, Nushell starts without XDG_CONFIG_HOME and so reads
  # ~/Library/Application Support/nushell. Point that at the chezmoi
  # managed ~/.config/nushell. env.nu there imports the rest of the
  # environment from a fish login shell.
  home-manager.users.mitchellh = { config, ... }: {
    home.file."Library/Application Support/nushell".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/nushell";
  };
}
