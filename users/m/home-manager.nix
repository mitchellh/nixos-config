{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  opencodeAwesome = import ./opencode/awesome.nix { inherit pkgs lib; };

  # Migration bridge: the canonical mountpoint is /Users/m/Projects, but during
  # the first nixos-rebuild switch that migrates the VM mountpoint, the new path
  # does not yet exist.  Fall back to /home/m/Projects so evaluation succeeds on
  # the old mount.  Once the switch completes the canonical path will be live and
  # this fallback becomes a no-op.
  projectsRoot =
    if builtins.pathExists /Users/m/Projects
    then /Users/m/Projects
    else /home/m/Projects;

  niriDeepDevBinary = "${toString projectsRoot}/yeet-and-yoink/target/release/yny";
  niriDeepZellijBreak = if isLinux then let
    rustToolchain = pkgs.rust-bin.stable.latest.default.override {
      targets = [ "wasm32-wasip1" ];
    };
    rustPlatform = pkgs.makeRustPlatform {
      cargo = rustToolchain;
      rustc = rustToolchain;
    };
  in rustPlatform.buildRustPackage {
    pname = "yeet-and-yoink-zellij-break";
    version = "0.1.0";
    src = lib.cleanSourceWith {
      src = projectsRoot + "/yeet-and-yoink/plugins/zellij-break";
      filter = path: type:
        let
          baseName = builtins.baseNameOf path;
        in
          baseName != "target" && baseName != ".git";
    };
    cargoLock.lockFile = projectsRoot + "/yeet-and-yoink/plugins/zellij-break/Cargo.lock";
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
  } else null;
  niriDeepZellijBreakPlugin = if isLinux then "${niriDeepZellijBreak}/yeet-and-yoink-zellij-break.wasm" else "";

  shellAliases = {
    g  = "git";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gl = "git prettylog";
    gp = "git push";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";

    l = "ls";
    lah = "eza -alh --color=auto --group-directories-first --icons";
    la = "eza -la";
    ll = "eza -lh --color=auto --group-directories-first --icons"; 
    magit = "emacsclient -a \"\" -nw -e -q '(progn (magit-status))'";
    "nix-gc" = "nix-collect-garbage -d";
    "nix-update-flakes" = "nix flake update";

    # cc = "claude";
    oc = "opencode";
    ocd = "opencode-dev";
    openspec-in-progress = "openspec list --json | jq -r '.changes[] | select(.status == \"in-progress\").name'";

    rs = "cargo";
    kubectl = "kubecolor";

    nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";

  } // (if isLinux then {
    pbcopy = "wl-copy --type text/plain";
    pbpaste = "wl-paste --type text/plain";
    open = "xdg-open";
    noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
    nix-config = "nvim /nix-config";
    niks = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake 'path:/nixos-config#vm-aarch64'";
    nikt = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --impure --flake 'path:/nixos-config#vm-aarch64'";
  } else (if isDarwin then {
    nix-config = "nvim ~/.config/nix-config";
    niks = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake '.#macbook-pro-m1'";
    nikt = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --impure --flake '.#macbook-pro-m1'";
  } else {}));

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
     cat "$1" | col -bx | bat --language man --style plain
   ''));
in {
  imports = [
    (import ./opencode/modules/home-manager.nix { inherit isWSL; })
  ];

  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  # Disabled for now since we mismatch our versions. See flake.nix for details.
  home.enableNixpkgsReleaseCheck = false;

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  home.packages = [
    pkgs.zellij
    pkgs.kitty
    pkgs.alacritty
    pkgs.uniclip  # Clipboard sharing (macOS <-> VM via SSH tunnel)
    pkgs.nerd-fonts.symbols-only  # icon font for Doom Emacs (+icons) and terminal apps
    pkgs.emacs-all-the-icons-fonts  # all-the-icons font family for Emacs

    pkgs.devenv

    # CLI tools
    pkgs.websocat
    pkgs.bat
    pkgs.eza
    pkgs.fd
    pkgs.bws
    pkgs.fzf
    pkgs.jq
    pkgs.fluxcd
    pkgs.kubecolor
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.rbw
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.yazi          # terminal file manager
    pkgs.btop          # system monitor
    pkgs.gnumake       # make
    pkgs.just          # command runner
    pkgs.tmux          # terminal multiplexer
    pkgs.tig           # git TUI
    pkgs.dust          # disk usage analyzer (du alternative)
    pkgs.zoxide

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

    # Node.js with npx (included) + fnm for version management
    pkgs.nodejs_22
    pkgs.fnm

    # ai tools - coding agents
    pkgs.agent-of-empires  # terminal session manager for AI agents
    pkgs.gastown  # gt - Gas Town multi-agent orchestration system
    pkgs.llm-agents.amp
    pkgs.llm-agents.ccusage-amp
    pkgs.llm-agents.eca
    pkgs.llm-agents.claude-code
    pkgs.llm-agents.ccusage
    pkgs.llm-agents.copilot-cli
    pkgs.llm-agents.pi
    pkgs.llm-agents.ccusage-pi
    pkgs.llm-agents.qwen-code
    pkgs.llm-agents.ccusage-opencode
    # pkgs.llm-agents.crush
    # pkgs.llm-agents.cursor-agent
    # pkgs.llm-agents.ccusage-codex
    # pkgs.llm-agents.forge
    # pkgs.llm-agents.qoder-cli
    # pkgs.llm-agents.code
    # pkgs.llm-agents.droid
    # pkgs.llm-agents.gemini-cli
    # pkgs.llm-agents.goose-cli
    # pkgs.llm-agents.jules
    # pkgs.llm-agents.kilocode-cli
    # pkgs.llm-agents.letta-code
    # pkgs.llm-agents.mistral-vibe
    # pkgs.llm-agents.nanocoder

    # ai tools - Claude Code ecosystem
    # pkgs.llm-agents.auto-claude
    # pkgs.llm-agents.catnip
    # pkgs.llm-agents.ccstatusline
    # pkgs.llm-agents.claude-code-router
    # pkgs.llm-agents.claude-plugins
    # pkgs.llm-agents.claudebox
    # pkgs.llm-agents.sandbox-runtime
    # pkgs.llm-agents.skills-installer

    # ai tools — ACP ecosystem
    # pkgs.llm-agents.claude-code-acp
    # pkgs.llm-agents.codex-acp

    # ai tools — usage analytics

    # ai tools — workflow & project management
    pkgs.llm-agents.beads  # bd — Beads CLI
    pkgs.llm-agents.beads-rust  # br - Beads CLI but faster (Rust), bv dependency  
    pkgs.llm-agents.beads-viewer  # bv — graph-aware TUI for Beads issue tracker
    pkgs.llm-agents.openspec
    pkgs.llm-agents.workmux
    # pkgs.llm-agents.agent-deck
    # pkgs.llm-agents.backlog-md
    # pkgs.llm-agents.cc-sdd
    # pkgs.llm-agents.chainlink
    # pkgs.llm-agents.spec-kit
    # pkgs.llm-agents.vibe-kanban

    # ai tools — code review
    # pkgs.llm-agents.coderabbit-cli
    # pkgs.llm-agents.tuicr

    # ai tools - .agents & AGENTS.md management
    pkgs.dotagents
    pkgs.apm

    # llm-agents.nix — utilities
    pkgs.llm-agents.copilot-language-server
    pkgs.llm-agents.openskills
    # pkgs.llm-agents.handy
    # pkgs.llm-agents.agent-browser
    # pkgs.llm-agents.coding-agent-search
    # pkgs.llm-agents.ck
    # pkgs.llm-agents.localgpt
    # pkgs.llm-agents.mcporter
    # pkgs.llm-agents.openclaw
    # pkgs.llm-agents.qmd

  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.ghostty-bin

    pkgs.skhd
    pkgs.cachix
    pkgs.gettext
    pkgs.sentry-cli
    pkgs.rsync         # newer rsync than macOS ships
    pkgs.sshpass       # non-interactive ssh password auth
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    # Wrapper scripts: inject secrets from rbw per-process (not global env)
    # gh is provided by programs.gh (with gitCredentialHelper); auth via shell function below
    # Claude Code uses native apiKeyHelper instead (see home.file below)
    # Called by Noctalia hooks/user-templates on wallpaper/dark-mode changes
    (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
      # Reload Noctalia theme in running Emacs daemon
      ${pkgs.emacs-pgtk}/bin/emacsclient -e \
        '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
        2>/dev/null || true
    '')

    pkgs.brave
    pkgs.docker-client  # CLI only; daemon runs on macOS host via Docker Desktop
    pkgs.ghostty
    pkgs.chromium
    pkgs.clang
    (pkgs.librewolf.override {
      extraPolicies = config.programs.librewolf.policies;
    })
    pkgs.pywalfox-native
    pkgs.activitywatch # automated time tracker (Linux only; Darwin via homebrew cask)
    pkgs.valgrind
    pkgs.foot         # lightweight Wayland terminal
    pkgs.grim         # screenshots
    pkgs.slurp        # region selection

    # inputs.niri-scratchpad.packages.${pkgs.system}.default # external scratchpad daemon/cli
    # Wayland utilities
    inputs.mangowc.packages.${pkgs.system}.default  # window control
    pkgs.wlr-which-key                              # which-key for wlroots

    # Wallpaper
    pkgs.git-repo-manager                           # declarative git repo sync

    # Bootstrap script - run once after fresh install
    (pkgs.writeShellScriptBin "setup-my-tools" ''
      set -e

      echo "==> Syncing git repositories..."
      ${pkgs.git-repo-manager}/bin/grm repos sync config --config ~/.config/grm/repos.yaml

      echo "==> Regenerating Noctalia color templates..."
      noctalia-shell ipc call colorscheme regenerate || true

      echo "==> Bootstrap complete!"
    '')
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionPath = lib.optionals isDarwin [
    "/Applications/VMware Fusion.app/Contents/Library"
  ];

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";
    NIRI_DEEP_ZELLIJ_BREAK_PLUGIN = niriDeepZellijBreakPlugin;

  } // (if isDarwin then {
    # See: https://github.com/NixOS/nixpkgs/issues/390751
    DISPLAY = "nixpkgs-390751";
  } else {}) // (if (isLinux && !isWSL) then {
    DOCKER_CONTEXT = "host-mac";
  } else {});

  home.file = {
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
  } // (if isDarwin then {
    # not gonna manage plists, but keep them here to remember
    # "Library/Preferences/com.MrKai77.Loop.plist".source = ./com.MrKai77.Loop.plist;
    # "Library/Preferences/com.brnbw.Leader-Key.plist".source = ./com.brnbw.Leader-Key.plist;
    # not ready yet to freeze it
    # "Library/Application Support/Leader Key/config.json".source = ./leader-key-config.json;
  } else {}) // (if isLinux then {
    # Claude Code apiKeyHelper: fetches token from rbw on demand (auto-refreshes every 5min)
    # ".claude/settings.json".text = builtins.toJSON {
    #   apiKeyHelper = "${pkgs.rbw}/bin/rbw get claude-oauth-token";
    # };
  } else {});


  xdg.configFile = {
    "grm/repos.yaml".source = ./grm-repos.yaml;
    "opencode/plugins/superpowers.js".source = opencodeAwesome.superpowersPlugin;
    "opencode/skills/superpowers" = {
      source = opencodeAwesome.superpowersSkillsDir;
      recursive = true;
    };
    "tmux/menus/doomux.sh" = {
      source = ./tmux/doomux.sh;
      executable = true;
    };
  } // (if isDarwin then {
    "wezterm/wezterm.lua".text = builtins.readFile ./wezterm.darwin.lua;
    "activitywatch/scripts" = {
      source = ./activitywatch;
      recursive = true;
    };
    "kanata-tray" = {
      source = ./kanata/tray;
      recursive = true;
    };
    "kanata" = {
      source = ./kanata/config-macbook-iso;
      recursive = true;
    };
  } else {}) // (if isLinux then {
    "wezterm/wezterm.lua".text = builtins.readFile ./wezterm.vm.lua;
    # Prevent home-manager from managing rbw config as a read-only store symlink;
    # the rbw-config systemd service writes the real config with sops email.
    "rbw/config.json".enable = lib.mkForce false;

    # wlr-which-key configuration
    "wlr-which-key/config.yaml".text = builtins.readFile ./wlr-which-key-config.yaml;

    # Noctalia user templates and theme template inputs
    "noctalia/user-templates.toml".source = ./noctalia-user-templates.toml;
    "noctalia/emacs-template.el".source = ./doom/themes/noctalia-template.el;
    "noctalia/wezterm-colors-template.lua".source = ./wezterm-colors-template.lua;
    "nvim/lua/matugen-template.lua".source = ./lazyvim/lua/matugen-template.lua;
  } else {});

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  # Doom Emacs (via nix-doom-emacs-unstraightened)
  programs.doom-emacs = {
    enable = true;
    doomDir = ./doom;
    emacs = pkgs.emacs-pgtk;
    # :config literate has no effect in unstraightened; tangle config.org at build time
    # tangleArgs = "--all config.org";
  };

  # Emacs daemon as a systemd user service (Linux only; macOS has no systemd)
  services.emacs = lib.mkIf isLinux {
    enable = true;
    defaultEditor = false; # we set EDITOR to nvim elsewhere
  };

  programs.gpg.enable = !isDarwin;

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

  programs.zellij = {
    enable = true;
    settings = {
      on_force_close = "quit";
    };
    settings.load_plugins = [
      "file:${niriDeepZellijBreakPlugin}"
    ];
  };

  programs.kitty = lib.mkIf (isLinux && !isWSL) {
    enable = true; # required for the default Hyprland config
    # set confirm_os_window_close 0
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
  # Enable Home Manager's SSH module so it owns ~/.ssh/config and the
  # mac-host-docker alias below can be managed declaratively.
  programs.ssh = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    matchBlocks."mac-host-docker" = {
      hostname = "192.168.130.1";
      user = "m";
      # This key is provisioned into the VM by `make vm/secrets`, which rsyncs
      # ~/.ssh/ from the macOS host.  The host's public key is already in
      # machines/generated/mac-host-authorized-keys and installed on the host
      # by darwin.nix, so authentication is fully deterministic.
      identityFile = "~/.ssh/id_ed25519";
      controlMaster = "auto";
      controlPersist = "10m";
      controlPath = "~/.ssh/control-%h-%p-%r";
      serverAliveInterval = 30;
    };
  };

  wayland.windowManager.hyprland = lib.mkIf (isLinux && !isWSL) {
    enable = true; # enable Hyprland
  };

  # Niri Wayland compositor configuration (Linux only)
  programs.niri.settings = lib.mkIf (isLinux && !isWSL) {
    hotkey-overlay = {
      skip-at-startup = true;
    };
    prefer-no-csd = true; # Client Side Decorations (title bars etc)
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
      # { command = [ "niri-scratchpad" "daemon" ]; }
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
      "Mod+Shift+T".action.spawn = "wezterm"; # explicit new instance

      "Mod+S".action.spawn = [
        niriDeepDevBinary "focus-or-cycle"
        "--app-id" "librewolf"
        "--spawn" "librewolf"
      ];
      "Mod+Shift+S".action.spawn = "librewolf"; # explicit new instance

      # Summon/toggle media app from any monitor/workspace.
      "Mod+P".action.spawn = [
        niriDeepDevBinary "focus-or-cycle"
        "--app-id" "spotify"
        "--spawn" "spotify"
        "--summon"
      ];

      # Scratchpads via niri-scratchpad registers.
      # "Mod+Grave".action.spawn = [ "niri-scratchpad" "create" "1" "--as-float" ];
      # "Mod+Shift+Grave".action.spawn = [ "niri-scratchpad" "create" "2" "--as-float" ];

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

      # # Screenshots
      # "Print".action.screenshot = {};
      # "Mod+Print".action.screenshot-window = {};

      # # Lock
      # "Mod+Escape".action.spawn = "swaylock";

      # Session
      # "Mod+Shift+E".action.quit = {};

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

  # niri-deep (Linux only)
  # programs.niri-deep = lib.mkIf (isLinux && !isWSL) {
  #   enable = true;
  #   # Mirrors runtime defaults in /Users/m/Projects/niri-deep/src/config.rs.
  #   config = {
  #     strategy = {
  #       move = "allow-composed";
  #       resize = "allow-composed";
  #     };

  #     wezterm = {
  #       focus.internal = true;
  #       resize.internal = true;
  #     };

  #     emacs = {
  #       move.tearout = true;
  #       resize.internal = true;
  #     };

  #     terminal.wezterm = {
  #       enable = true;
  #       mux.backend = "wezterm";
  #     };
  #   };
  # };

  # Wayprompt password prompt for Wayland sessions (Linux only)
  programs.wayprompt = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    package = pkgs.wayprompt;
  };

  # Mango Wayland compositor configuration (Linux only)
  wayland.windowManager.mango = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = builtins.readFile ./mangowc.cfg;
    autostart_sh = ''
      mako &
    '';
  };

  # Noctalia shell configuration (Linux VM only)
  programs.noctalia-shell = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = ./noctalia.json;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = shellAliases;
    initContent = ''
      # vscode shell integration (if running inside vscode, which is true for vscode terminal and false for external terminal; this allows us to use the same shell config in both without bloating the external terminal with vscode-specific stuff)
      [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

      # fnm (Node version manager)
      eval "$(fnm env --use-on-cd)"
      bindkey -v
      source ${./zsh-manydot.sh}

      # Doom-like leader key in zsh vi normal mode when running inside tmux.
      tmux-leader-menu() {
        if [[ -n "$TMUX" ]]; then
          tmux run-shell ~/.config/tmux/menus/doomux.sh
        else
          zle vi-forward-char
        fi
      }
      zle -N tmux-leader-menu
      bindkey -M vicmd " " tmux-leader-menu
    '' + (if isDarwin then ''

      # Homebrew
      eval "$(/opt/homebrew/bin/brew shellenv)"

      # NixOS VM management
      vm() { ~/.config/nix/docs/vm.sh "$@"; }
    '' else "") + (if isLinux then ''

      # gh: inject GITHUB_TOKEN per-invocation from rbw (no global env var)
      gh() { GITHUB_TOKEN=$(rbw get github-token) command gh "$@"; }

      # Ad-hoc API key injection (usage: with-openai some-command --flag)
      with-openai() { OPENAI_API_KEY=$(rbw get openai-api-key) "$@"; }
      with-amp() { AMP_API_KEY=$(rbw get amp-api-key) "$@"; }
      copilot() { COPILOT_GITHUB_TOKEN=$(rbw get github-token) command copilot "$@"; }
      claude() { CLAUDE_CODE_OAUTH_TOKEN=$(rbw get claude-oauth-token) command claude "$@"; }
      codex() { OPENAI_API_KEY=$(rbw get openai-api-key) command codex "$@"; }
    '' else "");
  };

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ./bashrc;
    shellAliases = shellAliases;
  };

  programs.direnv= {
    enable = true;

    config = {
      whitelist = {
        prefix= [
          "$HOME/code/go/src/github.com/hashicorp"
          "$HOME/code/go/src/github.com/smallstepman"
        ];

        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = false;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.atuin = {
    enable = true;
  };

  programs.oh-my-posh = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ./oh-my-posh.json);
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  # gh with credential helper: replaces credential.helper = "store"
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  # rbw (Bitwarden) configuration.
  # macOS: brew-managed, manual setup (`brew install rbw && rbw register`).
  # Linux/VM: Nix-managed package. Config file is written by the rbw-config
  #           systemd service (reads email from sops), NOT by home-manager.
  programs.rbw = lib.mkIf isLinux {
    enable = true;
    settings = {
      base_url = "https://api.bitwarden.eu";
      email = "overwritten-by-systemd";
      lock_timeout = 86400; # 24 hours
      pinentry = if isWSL then pkgs.pinentry-tty else pkgs.wayprompt;
    };
  };
  programs.git = {
    enable = true;
    signing = {
      key = "247AE5FC6A838272";
      signByDefault = true;
    };
    settings = {
      user.name = "Marcin Nowak Liebiediew";
      user.email = "m.liebiediew@gmail.com";
      gpg.program = if isDarwin then "/opt/homebrew/bin/gpg" else "${pkgs.gnupg}/bin/gpg";
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      # Git credentials handled by programs.gh.gitCredentialHelper
      github.user = "smallstepman";
      push.default = "tracking";
      init.defaultBranch = "main";
      aliases = {
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
        ce = "git commit --amend --no-edit";
      };
    };
  };
  
  programs.opencode = {
    enable = true;
    package = pkgs.llm-agents.opencode;
    settings = builtins.fromJSON (builtins.readFile ./opencode/settings.json);
    agents = opencodeAwesome.agents;
    commands = opencodeAwesome.commands;
    themes = opencodeAwesome.themes;
    rules = ''
      You are an intelligent and observant agent.
      
      You are on NixOS. Prefer `nix run nixpkgs#<tool>` over installing tools globally.
      If instructed to commit, do not use gpg signing.

      ## Agents
      Delegate tasks to subagents frequently.

      ## Think deeply about everything.
      Break problems down, abstract them out, understand the fundamentals.
    '';
  };

  programs.vscode = {
    enable = true;
    profiles = {
      default = {
        extensions = import ./vscode/extensions.nix { inherit pkgs; };
        keybindings = builtins.fromJSON (builtins.readFile ./vscode/keybindings.json);
        userSettings = builtins.fromJSON (builtins.readFile ./vscode/settings.json);
      };
    };
  };

  programs.go = {
    enable = true;
    env = { 
      GOPATH = "Documents/go";
      GOPRIVATE = [ "github.com/smallstepman" ];
    };
  };

  programs.lazyvim = {
    enable = true;
    configFiles = ./lazyvim;

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

  programs.librewolf = {
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

  mozilla.librewolfNativeMessagingHosts = lib.mkIf (isLinux && !isWSL) [ pkgs.pywalfox-native ];
  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

  # Keep package.json writable so opencode can update/install plugin deps at runtime.
  home.activation.ensureOpencodePackageJsonWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/opencode"
    packageJson="$HOME/.config/opencode/package.json"
    if [ -L "$packageJson" ]; then
      run rm -f "$packageJson"
    fi
    run cp ${./opencode/package.json} "$packageJson"
    run chmod u+w "$packageJson"
  '';

  # tmux-menus needs a writable plugin directory for cache files.
  home.activation.installWritableTmuxMenus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    src=${pkgs.tmuxPlugins."tmux-menus"}/share/tmux-plugins/tmux-menus
    dst="$HOME/.local/share/tmux/plugins/tmux-menus"
    run mkdir -p "$HOME/.local/share/tmux/plugins"
    run rm -rf "$dst"
    run cp -R "$src" "$dst"
    run chmod -R u+w "$dst"
  '';

  # Ensure writable output directories for Noctalia user templates
  home.activation.createNoctaliaThemeDirs = lib.mkIf (isLinux && !isWSL) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
  '');

  # Create the remote Docker context pointing at the macOS host daemon if missing.
  home.activation.ensureHostDockerContext = lib.mkIf (isLinux && !isWSL) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
      run ${pkgs.docker-client}/bin/docker context create host-mac \
        --docker "host=ssh://m@mac-host-docker"
    fi
  '');

  # ActivityWatch on Linux VM: watchers only, forwarding to macOS server
  # exposed locally via reverse SSH tunnel on 127.0.0.1:5600.
  systemd.user.services.activitywatch-watcher-afk = lib.mkIf (isLinux && !isWSL) {
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

  systemd.user.services.activitywatch-watcher-window = lib.mkIf (isLinux && !isWSL) {
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

  # Uniclip clipboard client: connects directly to macOS server at static IP
  systemd.user.services.uniclip = lib.mkIf (isLinux && !isWSL) {
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

  systemd.user.services.pywalfox-boot = lib.mkIf (isLinux && !isWSL) {
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

}
