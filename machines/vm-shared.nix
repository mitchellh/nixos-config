{ config, pkgs, lib, currentSystem, currentSystemName, inputs, ... }:

{
  sops.hostPubKey = lib.removeSuffix "\n" (builtins.readFile ./generated/vm-age-pubkey);

  imports = [ ];

  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  nixpkgs.config.permittedInsecurePackages = [
    # Needed for k2pdfopt 2.53.
    "mupdf-1.17.0"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  # Define your hostname.
  networking.hostName = "vm-macbook";
  networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];
  systemd.services.openwebui-local-proxy = {
    description = "Expose tunneled Open WebUI on localhost:80";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
      Restart = "always";
      RestartSec = 1;
    };
  };

  # Set your time zone.
  time.timeZone = "Europe/Warsaw";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;

  # Enable NetworkManager (was previously pulled in by GNOME)
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved = {
    enable = true;
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  };

  # Require password for sudo but cache it for 10 minutes.
  # Blocks automated privilege escalation (LLM agents, malicious deps)
  # while staying low-friction for interactive use.
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=10
  '';

  # Virtualization settings
  # No VM-local Docker daemon; host-Docker wiring (DOCKER_HOST) comes in a later task
  virtualisation.docker.enable = false;

  # Noctalia prerequisites (wifi/bluetooth/power/battery integrations)
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        fcitx5-hangul
        fcitx5-mozc
      ];
      # Use Wayland input method frontend instead of GTK_IM_MODULE
      # See: https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland
      fcitx5.waylandFrontend = true;
    };
  };

  # Enable tailscale. We manually authenticate when we want with
  # "sudo tailscale up". If you don't use tailscale, you should comment
  # out or delete all of this.
  services.tailscale.enable = true;
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth-key".path;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.mutableUsers = false;

  # Manage fonts. We pull these from a secret directory since most of these
  # fonts require a purchase.
  fonts = {
    fontDir.enable = true;

    packages = [
      pkgs.fira-code
      pkgs.jetbrains-mono
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    cachix
    gnumake
    git          # needed for niri-flake build
    killall
    wl-clipboard  # Wayland clipboard

    # WezTerm terminal
    pkgs.wezterm
  ] ++ lib.optionals (currentSystemName == "vm-aarch64") [
    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard sill works.
    gtkmm3
  ];

  # Enable niri (scrollable-tiling Wayland compositor)
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };

  # Enable Noctalia shell service for Wayland sessions
  services.noctalia-shell.enable = true;

  # Enable mango (Wayland compositor) - configured via home-manager
  programs.mango.enable = true;

  # greetd with tuigreet (minimal, stable, respects environment)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # Keep xserver for XWayland support
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";

  # Modifier remap via keyd
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        leftmeta = "leftcontrol";   # A
        leftcontrol = "leftalt";   # R
        leftalt = "leftmeta";        # S
        # leftshift = "leftshift";    # T
        # - 
        # rightshift = "rightshift";  # N
        rightalt = "rightmeta";      # E
        rightcontrol = "rightalt"; # I
        rightmeta = "rightcontrol"; # O
      };
    };
  };

  # Secrets management (sops-nix + sopsidy)
  # VM pubkey is read from machines/generated/vm-age-pubkey when present.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.generateKey = true;
  sops.age.sshKeyPaths = [];
  sops.gnupg.sshKeyPaths = [];
  sops.secrets."tailscale/auth-key" = {
    collect.rbw.id = "tailscale-auth-key";
  };
  sops.secrets."rbw/email" = {
    collect.rbw.id = "bitwarden-email";
    owner = "m";
    mode = "0400";
  };
  sops.secrets."uniclip/password" = {
    collect.rbw.id = "uniclip-password";
    owner = "m";
    mode = "0400";
  };
  sops.secrets."user/hashed-password" = {
    collect.rbw.id = "nixos-hashed-password";
    neededForUsers = true;
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.X11Forwarding = false;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.AllowUsers = [ "m" ];

  # escape hatches
  services.flatpak.enable = true;
  services.snap.enable = true;

  # Firewall: trust VMware NAT + Tailscale interfaces.
  # enp+ covers the VMware virtual NIC inside the guest (enp2s0).
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" "enp+" ];
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
