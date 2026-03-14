# den/aspects/features/darwin-core.nix
#
# Darwin system-core slice for macbook-pro-m1.
#
# Migrated from machines/macbook-pro-m1.nix (Task 9 of den migration).
# Covers: Determinate Nix integration, nix-daemon shell init, system package
# baseline, SSH daemon, Touch ID sudo, and the remaining Darwin user record
# fields that are not provided by den.provides.primary-user.
{ den, generated, ... }: {
  den.aspects.darwin-core = {
    includes = [
      ({ ... }: {
        darwin = { pkgs, ... }: {
          system.stateVersion = 5;

          # This makes it work with the Determinate Nix installer.
          ids.gids.nixbld = 30000;

          # We use the determinate-nix installer which manages Nix for us,
          # so we don't want nix-darwin to do it.
          nix.enable = false;
          nix.extraOptions = ''
            experimental-features = nix-command flakes
            keep-outputs = true
            keep-derivations = true
          '';

          # Enable the Linux builder so we can run Linux builds on our Mac.
          nix.linux-builder = {
            enable = false;
            ephemeral = true;
            maxJobs = 4;
            config = ({ pkgs, ... }: {
              virtualisation = {
                cores = 6;
                darwin-builder = {
                  diskSize = 100 * 1024; # 100GB
                  memorySize = 32 * 1024; # 32GB
                };
              };

              environment.systemPackages = [
                pkgs.htop
              ];
            });
          };

          nix.settings.trusted-users = [ "@admin" ];

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

          # The user already exists via den identity, but nix-darwin still needs
          # these Darwin-specific fields to know the home directory and host SSH
          # trust configuration for host/guest integration.
            users.users.m = {
              home = "/Users/m";
              openssh.authorizedKeys.keyFiles = [
                (generated.requireFile "mac-host-authorized-keys")
              ];
            };

          services.openssh.enable = true;
          services.openssh.extraConfig = ''
            # Only listen on the VMware host/guest interface so sshd is not reachable
            # from other network interfaces (Wi-Fi, Ethernet, etc.).
            ListenAddress 192.168.130.1
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
            X11Forwarding no
            AllowUsers m
          '';

          security.pam.services.sudo_local = {
            touchIdAuth = true;
            watchIdAuth = true;
            reattach = true;
          };
        };
      })
    ];
  };
}
