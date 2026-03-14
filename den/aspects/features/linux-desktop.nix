# den/aspects/features/linux-desktop.nix
#
# Linux graphical desktop stack aspect for user m's VM host.
#
# Migrated from the legacy VM shared and Home Manager entrypoints (Task 8
# of den migration).
#
# NixOS scope:
#   bluetooth, power-profiles-daemon, upower, fcitx5 input method,
#   programs.niri (enable + package), services.noctalia-shell,
#   programs.mango, services.greetd (tuigreet), services.xserver (XWayland),
#   services.keyd (modifier remap), desktop system packages (wl-clipboard,
#   wezterm).
#
# home-manager scope:
#   Linux desktop package set, xdg config files tied to the desktop stack,
#   programs.kitty, wayland.windowManager.hyprland, programs.wayprompt,
#   wayland.windowManager.mango, programs.noctalia-shell, programs.librewolf,
#   mozilla.librewolfNativeMessagingHosts, home.pointerCursor,
#   home.activation.createNoctaliaThemeDirs, activitywatch/pywalfox
#   systemd user services.
#
# Guarded by host.graphical.enable (set for vm-aarch64 in den/hosts.nix).
{ den, lib, inputs, ... }: {

  den.aspects.linux-desktop = {
    includes = [
        ({ host, ... }:
        let
          isGraphical = host.graphical.enable or false;
        in {
          nixos = { config, pkgs, lib, ... }: {
            imports = lib.optionals isGraphical [
              inputs.niri.nixosModules.niri
              inputs.mangowc.nixosModules.mango
              inputs.noctalia.nixosModules.default
            ];
          } // lib.optionalAttrs isGraphical {

            # ---------------------------------------------------------------
            # Hardware / power
            # ---------------------------------------------------------------

            # Noctalia prerequisites (wifi/bluetooth/power/battery integrations)
            hardware.bluetooth.enable = true;
            services.power-profiles-daemon.enable = true;
            services.upower.enable = true;

            # ---------------------------------------------------------------
            # Input method (desktop-adjacent, fcitx5 for Wayland)
            # ---------------------------------------------------------------

            i18n.inputMethod = {
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

            # ---------------------------------------------------------------
            # Desktop system packages (non-VMware plumbing)
            # ---------------------------------------------------------------

            environment.systemPackages = with pkgs; [
              wl-clipboard  # Wayland clipboard
              wezterm       # terminal emulator
            ];

            # ---------------------------------------------------------------
            # Wayland compositors
            # ---------------------------------------------------------------

            # Enable niri (scrollable-tiling Wayland compositor)
            programs.niri.enable = true;
            programs.niri.package = pkgs.niri-unstable;

            # Enable Noctalia shell service for Wayland sessions
            services.noctalia-shell.enable = true;

            # Enable mango (Wayland compositor) — configured via home-manager
            programs.mango.enable = true;

            # ---------------------------------------------------------------
            # Display manager
            # ---------------------------------------------------------------

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

            # ---------------------------------------------------------------
            # X / Wayland bridge
            # ---------------------------------------------------------------

            # Keep xserver enabled for XWayland support
            services.xserver.enable = true;
            services.xserver.xkb.layout = "us";

            # ---------------------------------------------------------------
            # Input remap (keyd)
            # ---------------------------------------------------------------

            # Modifier remap via keyd
            # Colemak-DH feel: A→Ctrl, R(leftCtrl)→Alt, S(leftAlt)→Meta,
            #                  E(rightAlt)→RightMeta, I(rightCtrl)→RightAlt,
            #                  O(rightMeta)→RightCtrl
            services.keyd = {
              enable = true;
              keyboards.default = {
                ids = [ "*" ];
                settings.main = {
                  leftmeta    = "leftcontrol";
                  leftcontrol = "leftalt";
                  leftalt     = "leftmeta";
                  rightalt    = "rightmeta";
                  rightcontrol = "rightalt";
                  rightmeta   = "rightcontrol";
                };
              };
            };
          };

          homeManager = { pkgs, lib, config, ... }: {
            # These HM modules must be imported unconditionally once this aspect is
            # active so their option declarations exist even where values are
            # individually gated with lib.mkIf.
            imports = [
              inputs.noctalia.homeModules.default  # programs.noctalia-shell
              inputs.mangowc.hmModules.mango       # wayland.windowManager.mango
            ];

            # ---------------------------------------------------------------
            # Linux desktop package set
            # ---------------------------------------------------------------

            home.packages = lib.mkIf isGraphical [
              # Called by Noctalia hooks/user-templates on wallpaper/dark-mode changes
              (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
                # Reload Noctalia theme in running Emacs daemon
                ${pkgs.emacs-pgtk}/bin/emacsclient -e \
                  '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
                  2>/dev/null || true
              '')

              pkgs.brave
              pkgs.ghostty
              pkgs.chromium
              pkgs.clang
              (pkgs.librewolf.override {
                extraPolicies = config.programs.librewolf.policies;
              })
              pkgs.pywalfox-native
              pkgs.activitywatch  # automated time tracker
              pkgs.valgrind
              pkgs.foot           # lightweight Wayland terminal
              pkgs.grim           # screenshots
              pkgs.slurp          # region selection

              inputs.mangowc.packages.${pkgs.stdenv.hostPlatform.system}.default  # window control
              pkgs.wlr-which-key                              # which-key for wlroots
              pkgs.git-repo-manager                           # declarative git repo sync

              # Bootstrap script — run once after fresh install
              (pkgs.writeShellScriptBin "setup-my-tools" ''
                set -e

                echo "==> Syncing git repositories..."
                ${pkgs.git-repo-manager}/bin/grm repos sync config --config ~/.config/grm/repos.yaml

                echo "==> Regenerating Noctalia color templates..."
                noctalia-shell ipc call colorscheme regenerate || true

                echo "==> Bootstrap complete!"
              '')
            ];

            # ---------------------------------------------------------------
            # XDG config files (Linux desktop stack)
            # ---------------------------------------------------------------

            xdg.configFile = lib.mkIf isGraphical {
              "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/vm/wezterm.lua;

              # Prevent home-manager from managing rbw config as a read-only store symlink;
              # the rbw-config systemd service writes the real config with sops email.
              "rbw/config.json".enable = lib.mkForce false;

              # wlr-which-key configuration
              "wlr-which-key/config.yaml".text = builtins.readFile ../../../dotfiles/by-host/vm/wlr-which-key-config.yaml;

              # Noctalia user templates and theme template inputs
              "noctalia/user-templates.toml".source = ../../../dotfiles/by-host/vm/noctalia-user-templates.toml;
              "noctalia/emacs-template.el".source = ../../../dotfiles/common/doom/themes/noctalia-template.el;
              "noctalia/wezterm-colors-template.lua".source = ../../../dotfiles/by-host/vm/wezterm-colors-template.lua;
              "nvim/lua/matugen-template.lua".source = ../../../dotfiles/common/lazyvim/lua/matugen-template.lua;
            };

            # ---------------------------------------------------------------
            # Programs
            # ---------------------------------------------------------------

            programs.kitty = lib.mkIf isGraphical {
              enable = true;  # required for the default Hyprland config
              settings = {
                confirm_os_window_close = 0;
                allow_remote_control = "socket-only";
                listen_on = "unix:@kitty-{kitty_pid}";
              };
              keybindings = {
                "ctrl+d" = "launch --location=hsplit --cwd=current";
                "ctrl+shift+d" = "launch --location=vsplit --cwd=current";
              };
            };

            wayland.windowManager.hyprland = lib.mkIf isGraphical {
              enable = true;
              settings = {
                # Minimal config to silence "no configuration" warning.
                # Hyprland is installed as a fallback compositor; Niri is primary.
                monitor = ",preferred,auto,1";
              };
            };

            programs.wayprompt = lib.mkIf isGraphical {
              enable = true;
              package = pkgs.wayprompt;
            };

            wayland.windowManager.mango = lib.mkIf isGraphical {
              enable = true;
              settings = builtins.readFile ../../../dotfiles/by-host/vm/mangowc.cfg;
              autostart_sh = ''
                mako &
              '';
            };

            programs.noctalia-shell = lib.mkIf isGraphical {
              enable = true;
              settings = ../../../dotfiles/by-host/vm/noctalia.json;
            };

            programs.librewolf = lib.mkIf isGraphical {
              enable = false;
              package = pkgs.librewolf;
              policies = {
                # Updates & Background Services
                AppAutoUpdate                 = false;
                BackgroundAppUpdate           = false;

                # Feature Disabling
                DisableBuiltinPDFViewer       = true;
                DisableFirefoxStudies         = true;
                DisableFirefoxAccounts        = true;
                DisableFirefoxScreenshots     = true;
                DisableForgetButton           = true;
                DisableMasterPasswordCreation = true;
                DisableProfileImport          = true;
                DisableProfileRefresh         = true;
                DisableSetDesktopBackground   = true;
                DisablePocket                 = true;
                DisableTelemetry              = true;
                DisableFormHistory            = true;
                DisablePasswordReveal         = true;

                # Access Restrictions
                BlockAboutConfig              = false;
                BlockAboutProfiles            = true;
                BlockAboutSupport             = true;

                # UI and Behavior
                DisplayMenuBar                = "never";
                DontCheckDefaultBrowser       = true;
                HardwareAcceleration          = false;
                OfferToSaveLogins             = false;
                DefaultDownloadDirectory      = "/home/m/Downloads";
                Cookies = {
                  "Allow" = [
                    "https://addy.io"
                    "https://element.io"
                    "https://discord.com"
                    "https://github.com"
                    "https://lemmy.cafe"
                    "https://proton.me"
                  ];
                  "Locked" = true;
                };
                ExtensionSettings = {
                  # Pywalfox (dynamic theming based on wallpaper colors)
                  "pywalfox@frewacom.org" = {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi";
                    installation_mode = "force_installed";
                  };
                  # uBlock Origin
                  "uBlock0@raymondhill.net" = {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                    installation_mode = "force_installed";
                  };
                  "addon@darkreader.org" = {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
                    installation_mode = "force_installed";
                  };
                  "vimium-c@gdh1995.cn" = {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-c/latest.xpi";
                    installation_mode = "force_installed";
                  };
                  "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
                    installation_mode = "force_installed";
                  };
                };
                FirefoxHome = {
                  "Search" = false;
                };
                Preferences = {
                  "browser.preferences.defaultPerformanceSettings.enabled" = false;
                  "browser.startup.homepage" = "about:home";
                  "browser.toolbar.bookmarks.visibility" = "newtab";
                  "browser.toolbars.bookmarks.visibility" = "newtab";
                  "browser.urlbar.suggest.bookmark" = false;
                  "browser.urlbar.suggest.engines" = false;
                  "browser.urlbar.suggest.history" = false;
                  "browser.urlbar.suggest.openpage" = false;
                  "browser.urlbar.suggest.recentsearches" = false;
                  "browser.urlbar.suggest.topsites" = false;
                  "browser.warnOnQuit" = false;
                  "browser.warnOnQuitShortcut" = false;
                  "places.history.enabled" = "false";
                  "privacy.resistFingerprinting" = true;
                  "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;
                };
              };
            };

            mozilla.librewolfNativeMessagingHosts = lib.mkIf isGraphical [ pkgs.pywalfox-native ];

            home.pointerCursor = lib.mkIf isGraphical {
              name = "Vanilla-DMZ";
              package = pkgs.vanilla-dmz;
              size = 128;
            };

            # ---------------------------------------------------------------
            # Activation scripts
            # ---------------------------------------------------------------

            # Ensure writable output directories for Noctalia user templates
            home.activation.createNoctaliaThemeDirs = lib.mkIf isGraphical (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
              '');

            # ---------------------------------------------------------------
            # Systemd user services (Linux desktop)
            # ---------------------------------------------------------------

            systemd.user.services.activitywatch-watcher-afk = lib.mkIf isGraphical {
              Unit = {
                Description = "ActivityWatch AFK watcher (remote macOS server)";
                After = [ "graphical-session.target" "network-online.target" ];
                Wants = [ "network-online.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-afk --host 127.0.0.1 --port 5600";
                Restart = "always";
                RestartSec = 5;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };

            systemd.user.services.activitywatch-watcher-window = lib.mkIf isGraphical {
              Unit = {
                Description = "ActivityWatch window watcher (remote macOS server)";
                After = [ "graphical-session.target" "network-online.target" ];
                Wants = [ "network-online.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-window --host 127.0.0.1 --port 5600";
                Restart = "always";
                RestartSec = 5;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };

            systemd.user.services.pywalfox-boot = lib.mkIf isGraphical {
              Unit = {
                Description = "Install and update Pywalfox for LibreWolf on boot";
                After = [ "graphical-session.target" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${pkgs.writeShellScript "pywalfox-boot" ''
                  set -euo pipefail
                  ${pkgs.pywalfox-native}/bin/pywalfox install --browser librewolf
                  ${pkgs.pywalfox-native}/bin/pywalfox update
                ''}";
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };
          };
        })
    ];
  };

}
