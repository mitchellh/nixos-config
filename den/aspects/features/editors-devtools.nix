# den/aspects/features/editors-devtools.nix
#
# Editors, developer tools, and terminal environment aspect for user m.
#
# Migrated from the legacy Home Manager entrypoint (Task 6 of den migration).
# Covers: developer package set, Doom Emacs, tmux, zellij (enable+force-close),
#         VSCode, Go, LazyVim, Starship, gdbinit, tmux menus, and the
#         installWritableTmuxMenus activation hook.
#
# Intentionally excluded (left in home-manager.nix for later tasks):
#   - programs.zellij.settings.load_plugins (Task 8 / impure niriDeep plugin)
#   - programs.kitty module config (Linux desktop / Task 7)
#   - programs.ssh, programs.niri, wayland.windowManager.*, programs.wayprompt
#   - programs.noctalia-shell, programs.librewolf, mozilla.*
#   - Linux/Darwin xdg.configFile entries except tmux menus
#   - systemd services except services.emacs
#   - projectsRoot / niriDeep* related logic
{ den, lib, inputs, ... }: {

  den.aspects.editors-devtools = {
    includes = [
      ({ host, ... }:
        let
          isDarwin = host.class == "darwin";
          isLinux  = host.class == "nixos";
        in {
          homeManager = { pkgs, lib, config, ... }: {

            # Load HM modules that are not part of the standard home-manager set.
            # These mirror the sharedModules in lib/mksystem.nix for the legacy path.
            imports = [
              inputs.nix-doom-emacs-unstraightened.homeModule
              inputs.lazyvim.homeManagerModules.default
            ];

            # -----------------------------------------------------------------
            # Packages
            # -----------------------------------------------------------------
            home.packages = [
              pkgs.nerd-fonts.symbols-only       # icon font for Doom Emacs (+icons)
              pkgs.emacs-all-the-icons-fonts      # all-the-icons font family for Emacs

              pkgs.devenv

              # CLI tools
              pkgs.websocat
              pkgs.bats
              pkgs.bws
              pkgs.yq
              pkgs.fluxcd
              pkgs.kubernetes-helm
              pkgs.tree
              pkgs.terragrunt
              pkgs.watch
              pkgs.yazi          # terminal file manager
              pkgs.btop          # system monitor
              pkgs.gnumake       # make
              pkgs.just          # command runner
              pkgs.dust          # disk usage analyzer (du alternative)

              # dev tools
              pkgs.go
              pkgs.gopls

              # Rust toolchain (via rust-overlay)
              (pkgs.rust-bin.stable.latest.default.override {
                extensions = [ "rust-src" "rust-analyzer" ];
                targets = [ "wasm32-wasip1" ];
              })

              # Python + uv (hiPrio so it wins over python3 bundled in pkgs.apm)
              (lib.hiPrio pkgs.python314)
              pkgs.uv

              # Node.js with npx (included)
              pkgs.nodejs_22

              # Terminal emulators / multiplexers
              pkgs.zellij
              pkgs.kitty
              pkgs.alacritty
              pkgs.uniclip  # Clipboard sharing (macOS <-> VM over a direct TCP connection)
            ];

            # -----------------------------------------------------------------
            # Dotfiles
            # -----------------------------------------------------------------
            home.file.".gdbinit".source = ../../../dotfiles/common/gdbinit;

            # -----------------------------------------------------------------
            # XDG config files
            # -----------------------------------------------------------------
            xdg.configFile."tmux/menus/doomux.sh" = {
              source = ../../../dotfiles/common/tmux/doomux.sh;
              executable = true;
            };

            # -----------------------------------------------------------------
            # Activation hooks
            # -----------------------------------------------------------------

            # tmux-menus needs a writable plugin directory for cache files.
            home.activation.installWritableTmuxMenus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              src=${pkgs.tmuxPlugins."tmux-menus"}/share/tmux-plugins/tmux-menus
              dst="$HOME/.local/share/tmux/plugins/tmux-menus"
              run mkdir -p "$HOME/.local/share/tmux/plugins"
              run rm -rf "$dst"
              run cp -R "$src" "$dst"
              run chmod -R u+w "$dst"
            '';

            # -----------------------------------------------------------------
            # Doom Emacs
            # -----------------------------------------------------------------
            programs.doom-emacs = {
              enable = true;
              doomDir = ../../../dotfiles/common/doom;
              emacs = pkgs.emacs-pgtk;
            };

            # Emacs daemon as a systemd user service (Linux only; macOS has no systemd)
            services.emacs = lib.mkIf isLinux {
              enable = true;
              defaultEditor = false; # we set EDITOR to nvim elsewhere
            };

            # -----------------------------------------------------------------
            # Tmux
            # -----------------------------------------------------------------
            programs.tmux = {
              enable = true;
              keyMode = "vi";
              mouse = true;
              extraConfig = ''
                set -g @menus_location_x 'C'
                set -g @menus_trigger 'Space'
                set -g @menus_main_menu '${config.home.homeDirectory}/.config/tmux/menus/doomux.sh'
                set -g @menus_display_commands 'No'
                run-shell ~/.local/share/tmux/plugins/tmux-menus/menus.tmux
                set -g status-keys vi
                setw -g mode-keys vi
                set -g base-index 1
                setw -g pane-base-index 1
                set -g renumber-windows on
                set -g set-clipboard on
              '';
            };

            # -----------------------------------------------------------------
            # Zellij (enable + force-close only; load_plugins stays in legacy)
            # -----------------------------------------------------------------
            programs.zellij = {
              enable = true;
              settings = {
                on_force_close = "quit";
              };
            };

            # -----------------------------------------------------------------
            # VSCode
            # -----------------------------------------------------------------
            programs.vscode = {
              enable = true;
              profiles = {
                default = {
                  extensions = import ../../../dotfiles/common/vscode/extensions.nix { inherit pkgs; };
                  keybindings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/vscode/keybindings.json);
                  userSettings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/vscode/settings.json);
                };
              };
            };

            # -----------------------------------------------------------------
            # Go
            # -----------------------------------------------------------------
            programs.go = {
              enable = true;
              env = {
                GOPATH = "Documents/go";
                GOPRIVATE = [ "github.com/smallstepman" ];
              };
            };

            # -----------------------------------------------------------------
            # LazyVim
            # -----------------------------------------------------------------
            programs.lazyvim = {
              enable = true;
              configFiles = ../../../dotfiles/common/lazyvim;

              extras = {
                lang.nix.enable = true;
                lang.python = {
                  enable = true;
                  installDependencies = true;        # Install ruff
                  installRuntimeDependencies = true; # Install python3
                };
                lang.go = {
                  enable = true;
                  installDependencies = true;        # Install gopls, gofumpt, etc.
                  installRuntimeDependencies = true; # Install go compiler
                };
                lang.typescript = {
                  enable = true;
                  installDependencies = false;        # Skip typescript tools
                  installRuntimeDependencies = true;  # But install nodejs
                };
                lang.rust.enable = true;
                ai.copilot.enable = true;
              };

              # Additional packages (optional)
              extraPackages = with pkgs; [
                nixd        # Nix LSP
                alejandra   # Nix formatter
                pyright     # Python LSP
              ];

              # Only needed for languages not covered by LazyVim extras
              treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
                templ     # Go templ files
              ];
            };

            # -----------------------------------------------------------------
            # Starship (disabled; config preserved for when it is re-enabled)
            # -----------------------------------------------------------------
            programs.starship = {
              enable = false;
              settings = builtins.fromTOML (builtins.readFile ../../../dotfiles/common/starship.toml);
            };

          };
        })
    ];
  };

}
