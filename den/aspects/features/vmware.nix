# den/aspects/features/vmware.nix
#
# VMware guest integration and VM-specific host-bridge behavior for user m.
#
# Migrated from the legacy vm-aarch64 and Home Manager entrypoints (Task 8
# of den migration).
#
# NixOS scope:
#   nixpkgs.config.allowUnfree + allowUnsupportedSystem,
#   virtualisation.vmware.guest.enable, HGFS mounts (/nixos-config,
#   /nixos-generated, and /Users/m/Projects), gtkmm3 (VMware clipboard
#   integration).
#
# home-manager scope:
#   projectsRoot fallback logic, niriDeep plugin build (yeet-and-yoink),
#   NIRI_DEEP_ZELLIJ_BREAK_PLUGIN + DOCKER_CONTEXT session variables,
#   programs.zellij.settings.load_plugins (niri-deep plugin),
#   programs.ssh (mac-host-docker matchBlock),
#   programs.niri.settings (full HM Niri config — depends on niriDeep bindings),
#   home.activation.ensureHostDockerContext,
#   systemd.user.services.uniclip,
#   docker-client package.
#
# Guarded by host.vmware.enable (set for vm-aarch64 in den/hosts.nix).
{ den, lib, yeetAndYoink, ... }: {

  den.aspects.vmware = {
    includes = [
      ({ host, ... }:
        let
          isVM = host.vmware.enable or false;
        in {
          nixos = { config, pkgs, lib, ... }: lib.mkIf isVM {

            # Nixpkgs config
            # ---------------------------------------------------------------

            # Lots of aarch64 stuff claims not to work, but actually works.
            nixpkgs.config.allowUnfree = true;
            nixpkgs.config.allowUnsupportedSystem = true;

            # ---------------------------------------------------------------
            # VMware guest tools
            # ---------------------------------------------------------------

            # This works through our custom module imported in den/default.nix.
            virtualisation.vmware.guest.enable = true;

            # VMware guest packages (clipboard integration)
            # gtkmm3 is needed for the vmware user tools clipboard to work.
            environment.systemPackages = [ pkgs.gtkmm3 ];

            # ---------------------------------------------------------------
            # HGFS mounts (VMware shared folders)
            # ---------------------------------------------------------------

            # Note: VMware HGFS shows all files as executable (755) because
            # macOS doesn't distinguish file modes the same way. We accept this
            # and use git's core.fileMode=false (set in home-manager) to ignore
            # mode differences.

            fileSystems."/nixos-config" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/nixos-config";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };

            fileSystems."/nixos-generated" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/nixos-generated";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };

            fileSystems."/Users/m/Projects" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/Projects";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };
          };

          homeManager = { pkgs, lib, config, ... }: lib.mkIf isVM (
            let
              # Migration bridge: the canonical mountpoint is /Users/m/Projects, but
              # during the first nixos-rebuild switch that migrates the VM mountpoint
              # the new path does not yet exist. Fall back to /home/m/Projects so
              # evaluation succeeds on the old mount. Once the switch completes the
              # canonical path will be live and this fallback becomes a no-op.
              projectsRoot =
                if builtins.pathExists /Users/m/Projects
                then /Users/m/Projects
                else /home/m/Projects;

              niriDeepDevBinary = "${toString projectsRoot}/yeet-and-yoink/target/release/yny";

              niriDeepZellijBreak =
                let
                  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
                    targets = [ "wasm32-wasip1" ];
                  };
                  rustPlatform = pkgs.makeRustPlatform {
                    cargo = rustToolchain;
                    rustc = rustToolchain;
                  };
                in
                  rustPlatform.buildRustPackage {
                    pname = "yeet-and-yoink-zellij-break";
                    version = "0.1.0";
                    src = lib.cleanSourceWith {
                      src = yeetAndYoink.root;
                      filter = path: type:
                        let
                          baseName = builtins.baseNameOf path;
                        in
                          baseName != "target" && baseName != ".git";
                    };
                    cargoLock.lockFile = yeetAndYoink.requirePath "Cargo.lock";
                    buildPhase = ''
                      runHook preBuild
                      cargo build --frozen --release --target wasm32-wasip1
                      runHook postBuild
                    '';
                    doCheck = false;
                    installPhase = ''
                      runHook preInstall
                      mkdir -p $out
                      if [ -f target/wasm32-wasip1/release/yeet-and-yoink-zellij-break.wasm ]; then
                        install -m0644 target/wasm32-wasip1/release/yeet-and-yoink-zellij-break.wasm $out/yeet-and-yoink-zellij-break.wasm
                      else
                        echo "yeet-and-yoink-zellij-break.wasm not found after build" >&2
                        exit 1
                      fi
                      runHook postInstall
                    '';
                  };

              niriDeepZellijBreakPlugin = "${niriDeepZellijBreak}/yeet-and-yoink-zellij-break.wasm";
            in {
              # ---------------------------------------------------------------
              # Packages (VM-specific)
              # ---------------------------------------------------------------

              home.packages = [
                pkgs.docker-client  # CLI only; daemon runs on macOS host via Docker Desktop
              ];

              # ---------------------------------------------------------------
              # Session variables
              # ---------------------------------------------------------------

              home.sessionVariables = {
                NIRI_DEEP_ZELLIJ_BREAK_PLUGIN = niriDeepZellijBreakPlugin;
                DOCKER_CONTEXT = "host-mac";
              };

              # ---------------------------------------------------------------
              # Programs
              # ---------------------------------------------------------------

              # zellij: load_plugins references the niriDeep plugin built above.
              programs.zellij.settings.load_plugins = [
                "file:${niriDeepZellijBreakPlugin}"
              ];

              # Enable Home Manager's SSH module so it owns ~/.ssh/config and
              # the mac-host-docker alias below can be managed declaratively.
              programs.ssh = {
                enable = true;
                enableDefaultConfig = false;  # suppress future deprecation warning
                matchBlocks."mac-host-docker" = {
                  hostname = "192.168.130.1";
                  user = "m";
                  # This expects the matching private key to be available in the VM
                  # at ~/.ssh/id_ed25519.
                  identityFile = "~/.ssh/id_ed25519";
                  controlMaster = "auto";
                  controlPersist = "10m";
                  controlPath = "~/.ssh/control-%h-%p-%r";
                  serverAliveInterval = 30;
                };
              };

              # Niri Wayland compositor configuration
              # Full config lives here because it depends heavily on niriDeep
              # plugin bindings which are VM-specific.
              programs.niri.settings = {
                hotkey-overlay = {
                  skip-at-startup = true;
                };
                prefer-no-csd = true;  # Client Side Decorations (title bars etc)
                input = {
                  mod-key = "Alt";  # Ctrl ; Alt; Super;
                  keyboard.xkb.layout = "us";
                  keyboard.repeat-delay = 150;
                  keyboard.repeat-rate = 50;
                  touchpad = {
                    tap = true;
                    natural-scroll = true;
                  };
                };

                window-rules = [
                  {
                    geometry-corner-radius = {
                      top-left = 12.0;
                      top-right = 12.0;
                      bottom-right = 12.0;
                      bottom-left = 12.0;
                    };
                  }
                  {
                    clip-to-geometry = true;
                  }
                ];

                outputs."Virtual-1".scale = 2.0;

                layout = {
                  always-center-single-column = true;
                  gaps = 16;
                  center-focused-column = "never";
                  preset-column-widths = [
                    { proportion = 1.0 / 3.0; }
                    { proportion = 1.0 / 2.0; }
                    { proportion = 2.0 / 3.0; }
                  ];
                  default-column-width.proportion = 0.5;
                  focus-ring = {
                    width = 2;
                    active.color = "#7fc8ff";
                    inactive.color = "#505050";
                  };
                };

                spawn-at-startup = [
                  { command = [ "mako" ]; }
                ];

                workspaces = {
                  "stash" = { };
                };

                environment = {
                  NIXOS_OZONE_WL = "1";
                  NIRI_DEEP_ZELLIJ_BREAK_PLUGIN = niriDeepZellijBreakPlugin;
                };

                binds = {
                  # Launch
                  "Mod+T".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "org.wezfurlong.wezterm"
                    "--spawn" "wezterm"
                  ];
                  "Mod+Shift+T".action.spawn = "wezterm";  # explicit new instance

                  "Mod+S".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "librewolf"
                    "--spawn" "librewolf"
                  ];
                  "Mod+Shift+S".action.spawn = "librewolf";  # explicit new instance

                  # Summon/toggle media app from any monitor/workspace.
                  "Mod+P".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "spotify"
                    "--spawn" "spotify"
                    "--summon"
                  ];

                  "Mod+Space".action.spawn = "wlr-which-key";
                  "Mod+Q".action.close-window = {};

                  # Layout
                  "Mod+R".action.switch-preset-column-width = {};
                  "Mod+F".action.maximize-column = {};
                  "Mod+Shift+F".action.fullscreen-window = {};
                  "Mod+Minus".action.set-column-width = "-10%";
                  "Mod+Equal".action.set-column-width = "+10%";
                  "Mod+W".action.toggle-column-tabbed-display = {};
                  "Mod+Slash".action.toggle-overview = {};

                  # Focus (deep: navigates within app splits first, then niri columns)
                  "Mod+N".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "west" ];
                  "Mod+E".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "south" ];
                  "Mod+I".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "north" ];
                  "Mod+O".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "east" ];

                  # Move (deep: tears app buffers into new windows at boundaries)
                  "Mod+H".action.consume-or-expel-window-left = {};
                  "Mod+L".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "west" ];
                  "Mod+U".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "south" ];
                  "Mod+Y".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "north" ];
                  "Mod+Semicolon".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "east" ];
                  "Mod+Return".action.consume-or-expel-window-right = {};

                  # Workspaces
                  "Mod+f1".action.focus-workspace = 1;
                  "Mod+f2".action.focus-workspace = 2;
                  "Mod+f3".action.focus-workspace = 3;
                  "Mod+f4".action.focus-workspace = 4;
                  "Mod+f5".action.focus-workspace = 5;
                  "Mod+f6".action.focus-workspace = 6;
                  "Mod+f7".action.focus-workspace = 7;
                  "Mod+f8".action.focus-workspace = 8;
                  "Mod+f9".action.focus-workspace = 9;

                  "Shift+f1".action.move-column-to-workspace = 1;
                  "Shift+f2".action.move-column-to-workspace = 2;
                  "Shift+f3".action.move-column-to-workspace = 3;
                  "Shift+f4".action.move-column-to-workspace = 4;
                  "Shift+f5".action.move-column-to-workspace = 5;
                  "Shift+f6".action.move-column-to-workspace = 6;
                  "Shift+f7".action.move-column-to-workspace = 7;
                  "Shift+f8".action.move-column-to-workspace = 8;
                  "Shift+f9".action.move-column-to-workspace = 9;
                };
              };

              # ---------------------------------------------------------------
              # Activation scripts
              # ---------------------------------------------------------------

              # Create the remote Docker context pointing at the macOS host
              # daemon if missing.
              home.activation.ensureHostDockerContext =
                lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
                    run ${pkgs.docker-client}/bin/docker context create host-mac \
                      --docker "host=ssh://m@mac-host-docker"
                  fi
                '';

              # ---------------------------------------------------------------
              # Systemd user services (VMware / host-bridge)
              # ---------------------------------------------------------------

              # Uniclip clipboard client: connects directly to macOS server at
              # static VMware NAT IP.
              systemd.user.services.uniclip = {
                Unit = {
                  Description = "Uniclip clipboard client (direct connection to macOS server)";
                  After = [ "graphical-session.target" ];
                };
                Service = {
                  Type = "simple";
                  ExecStart = "${pkgs.writeShellScript "uniclip-client" ''
                    set -euo pipefail
                    export XDG_RUNTIME_DIR=/run/user/$(id -u)
                    export PATH=${lib.makeBinPath [ pkgs.wl-clipboard ]}:$PATH
                    if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
                      export WAYLAND_DISPLAY=wayland-1
                    elif [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
                      export WAYLAND_DISPLAY=wayland-0
                    else
                      echo "uniclip: no wayland socket found in $XDG_RUNTIME_DIR" >&2
                      exit 1
                    fi
                    if [ ! -r /run/secrets/uniclip/password ]; then
                      echo "uniclip: /run/secrets/uniclip/password is missing" >&2
                      exit 1
                    fi
                    UNICLIP_PASSWORD="$(cat /run/secrets/uniclip/password)"
                    if [ -z "$UNICLIP_PASSWORD" ]; then
                      echo "uniclip: empty password from /run/secrets/uniclip/password" >&2
                      exit 1
                    fi
                    export UNICLIP_PASSWORD
                    exec ${pkgs.uniclip}/bin/uniclip --secure 192.168.130.1:53701
                  ''}";
                  Restart = "on-failure";
                  RestartSec = 5;
                };
                Install.WantedBy = [ "graphical-session.target" ];
              };
            }
          );
        })
    ];
  };

}
