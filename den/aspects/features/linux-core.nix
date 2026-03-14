# den/aspects/features/linux-core.nix
#
# Core Linux system configuration aspect.
#
# Migrated from the legacy VM shared and Linux user entrypoints (Task 7 of den migration).
# Covers: boot/kernel/Nix settings, networking, sudo, OpenSSH, flatpak/snap, firewall,
#         fonts, locale, nix-ld, zsh, localBinInPath, and common system packages.
#
# Explicitly OUT of scope (remain in legacy for Task 8+):
#   Desktop/Wayland/Niri/Mango/Noctalia, greetd, xserver, keyd, hardware.bluetooth,
#   power-profiles-daemon, upower, i18n.inputMethod, wezterm, gtkmm3.
{ den, lib, inputs, ... }: {

  den.aspects.linux-core = {
      includes = [
        ({ host, ... }: {
          nixos = { config, pkgs, lib, ... }: {
            imports = [
              inputs.nix-snapd.nixosModules.default
            ];

            # ---------------------------------------------------------------
            # Boot / kernel
            # ---------------------------------------------------------------

          # Be careful updating this.
          boot.kernelPackages = pkgs.linuxPackages_latest;

          # Use the systemd-boot EFI boot loader.
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          # VMware, Parallels both only support this being 0 otherwise you see
          # "error switching console mode" on boot.
          boot.loader.systemd-boot.consoleMode = "0";

          # ---------------------------------------------------------------
          # Nix / nixpkgs
          # ---------------------------------------------------------------

          nix.package = pkgs.nixVersions.latest;
          nix.extraOptions = ''
            keep-outputs = true
            keep-derivations = true
          '';
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          nixpkgs.config.permittedInsecurePackages = [
            # Needed for k2pdfopt 2.53.
            "mupdf-1.17.0"
          ];

          # ---------------------------------------------------------------
          # Time / locale
          # ---------------------------------------------------------------

          time.timeZone = "Europe/Warsaw";

          i18n.defaultLocale = "en_US.UTF-8";

          # ---------------------------------------------------------------
          # Networking
          # ---------------------------------------------------------------

          # The global useDHCP flag is deprecated, therefore explicitly set to false here.
          networking.useDHCP = false;

          # Enable NetworkManager
          networking.networkmanager.enable = true;
          networking.networkmanager.dns = "systemd-resolved";
          services.resolved = {
            enable = true;
            fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
          };

          # Firewall: trust Tailscale + VMware NAT interfaces.
          # enp+ covers the VMware virtual NIC inside the guest (enp2s0).
          networking.firewall = {
            enable = true;
            trustedInterfaces = [ "tailscale0" "enp+" ];
            allowedTCPPorts = [ 22 ];
            allowedUDPPorts = [ config.services.tailscale.port ];
          };

          # ---------------------------------------------------------------
          # Security / sudo
          # ---------------------------------------------------------------

          # Require password for sudo but cache it for 10 minutes.
          # Blocks automated privilege escalation (LLM agents, malicious deps)
          # while staying low-friction for interactive use.
          security.sudo.wheelNeedsPassword = true;
          security.sudo.extraConfig = ''
            Defaults timestamp_timeout=10
          '';

          # ---------------------------------------------------------------
          # Virtualization
          # ---------------------------------------------------------------

          # No VM-local Docker daemon; host-Docker wiring (DOCKER_HOST) comes in a later task.
          virtualisation.docker.enable = false;

          # ---------------------------------------------------------------
          # Services
          # ---------------------------------------------------------------

          # Enable the OpenSSH daemon.
          services.openssh.enable = true;
          services.openssh.settings.PasswordAuthentication = false;
          services.openssh.settings.KbdInteractiveAuthentication = false;
          services.openssh.settings.X11Forwarding = false;
          services.openssh.settings.PermitRootLogin = "no";
          services.openssh.settings.AllowUsers = [ "m" ];

          # Escape hatches for user-installed apps.
          services.flatpak.enable = true;
          services.snap.enable = true;

          # ---------------------------------------------------------------
          # Fonts
          # ---------------------------------------------------------------

          fonts.fontDir.enable = true;
          fonts.packages = [
            pkgs.fira-code
            pkgs.jetbrains-mono
          ];

          # ---------------------------------------------------------------
          # System packages (core / non-desktop)
          # ---------------------------------------------------------------

          environment.systemPackages = with pkgs; [
            cachix
            gnumake
            git
            killall
          ];

          # ---------------------------------------------------------------
          # Shell / environment (from the legacy Linux user entrypoint)
          # ---------------------------------------------------------------

          # https://github.com/nix-community/home-manager/pull/2408
          environment.pathsToLink = [ "/share/zsh" ];

          # Add ~/.local/bin to PATH
          environment.localBinInPath = true;

          # Since we're using zsh as our shell
          programs.zsh.enable = true;

          # We require this because we use lazy.nvim against the best wishes
          # of a pure Nix system so this lets those unpatched binaries run.
          programs.nix-ld.enable = true;
          programs.nix-ld.libraries = with pkgs; [
            # Add any missing dynamic libraries for unpackaged programs
            # here, NOT in environment.systemPackages
          ];

          # ---------------------------------------------------------------
          # State version
          # ---------------------------------------------------------------

          # This value determines the NixOS release from which the default
          # settings for stateful data, like file locations and database versions
          # on your system were taken. It's perfectly fine and recommended to leave
          # this value at the release version of the first install of this system.
          # Before changing this value read the documentation for this option
          # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
          system.stateVersion = "25.11"; # Did you read the comment?
        };
      })
    ];
  };

}
