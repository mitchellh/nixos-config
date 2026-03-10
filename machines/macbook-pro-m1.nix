{ config, pkgs, ... }: {
  # Set in Sept 2024 as part of the macOS Sequoia release.
  system.stateVersion = 5;

  # This makes it work with the Determinate Nix installer
  ids.gids.nixbld = 30000;

  # We use proprietary software on this machine
  nixpkgs.config.allowUnfree = true;

  # Keep in async with vm-shared.nix. (todo: pull this out into a file)
  nix = {
    # We use the determinate-nix installer which manages Nix for us,
    # so we don't want nix-darwin to do it.
    enable = false;

    # We need to enable flakes
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';

    # Enable the Linux builder so we can run Linux builds on our Mac.
    # This can be debugged by running `sudo ssh linux-builder`
    linux-builder = {
      enable = false;
      ephemeral = true;
      maxJobs = 4;
      config = ({ pkgs, ... }: {
        # Make our builder beefier since we're on a beefy machine.
        virtualisation = {
          cores = 6;
          darwin-builder = {
            diskSize = 100 * 1024; # 100GB
            memorySize = 32 * 1024; # 32GB
          };
        };

        # Add some common debugging tools we can see whats up.
        environment.systemPackages = [
          pkgs.htop
        ];
      });
    };

    settings = {
      # Required for the linux builder
      trusted-users = ["@admin"];
    };
  };

  # Determinate's nix.conf may not include nix.custom.conf; manage both.
  environment.etc."nix/nix.conf".text = ''
    build-users-group = nixbld
    !include /etc/nix/nix.custom.conf
  '';

  environment.etc."nix/nix.custom.conf".text = ''
    experimental-features = nix-command flakes
  '';

  # Make ad-hoc nixpkgs usage honor unfree defaults.
  environment.etc."nixpkgs/config.nix".text = ''
    { allowUnfree = true; }
  '';

  # zsh is the default shell on Mac and we want to make sure that we're
  # configuring the rc correctly with nix-darwin paths.
  programs.zsh.enable = true;
  programs.zsh.shellInit = ''
    # Nix
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
      . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
    # End Nix
    '';

  programs.fish.enable = true;
  programs.fish.shellInit = ''
    # Nix
    if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
      source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
    end
    # End Nix
    '';

  environment.shells = with pkgs; [ bashInteractive zsh fish ];
  environment.systemPackages = with pkgs; [
    cachix
  ];

  # SSH daemon used by the VM to reach the host Docker socket.
  # nix-darwin does not expose a structured `.settings` attribute like NixOS does,
  # so all sshd_config directives must be supplied via `extraConfig`.
  services.openssh = {
    enable = true;
    extraConfig = ''
      # Only listen on the VMware host/guest interface so sshd is not reachable
      # from other network interfaces (Wi-Fi, Ethernet, etc.).
      ListenAddress 192.168.130.1
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      X11Forwarding no
      AllowUsers m
    '';
  };

  # sudo with Touch ID and Apple Watch
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
    reattach = true;
  };
}
