# den/aspects/features/home-base.nix
#
# Residual Home Manager configuration for user m that was never exercised by the
# temporary legacy bridge.
#
# Migrated from the legacy Home Manager entrypoint during Task 11 of the den migration.
# Covers:
#   - Darwin-only home.packages additions
#   - shared XDG config for git-repo-manager
#   - Darwin-only XDG config files used by launchd/user tooling
#   - Linux rbw home-manager module settings
{ den, lib, ... }: {
  den.aspects.home-base = {
    includes = [
      ({ host, ... }:
        let
          isDarwin = host.class == "darwin";
          isLinux = host.class == "nixos";
          isWSL = host.wsl.enable or false;
        in {
          homeManager = { pkgs, lib, ... }: {
            home.packages = lib.optionals isDarwin [
              pkgs.ghostty-bin
              pkgs.skhd
              pkgs.cachix
              pkgs.gettext
              pkgs.sentry-cli
              pkgs.rsync
              pkgs.sshpass
            ];

            xdg.configFile = {
              "grm/repos.yaml".source = ../../../dotfiles/common/grm-repos.yaml;
            } // (lib.optionalAttrs isDarwin {
              "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/darwin/wezterm.lua;
              "activitywatch/scripts" = {
                source = ../../../dotfiles/by-host/darwin/activitywatch;
                recursive = true;
              };
              "kanata-tray" = {
                source = ../../../dotfiles/by-host/darwin/kanata/tray;
                recursive = true;
              };
              "kanata" = {
                source = ../../../dotfiles/by-host/darwin/kanata/config-macbook-iso;
                recursive = true;
              };
            });

            # rbw config is managed declaratively on Linux, but the actual
            # config.json file remains writable so the rbw-config user service can
            # inject the sops-provided email at login.
            programs.rbw = lib.mkIf isLinux {
              enable = true;
              settings = {
                base_url = "https://api.bitwarden.eu";
                email = "overwritten-by-systemd";
                lock_timeout = 86400;
                pinentry = if isWSL then pkgs.pinentry-tty else pkgs.wayprompt;
              };
            };
          };
        })
    ];
  };
}
