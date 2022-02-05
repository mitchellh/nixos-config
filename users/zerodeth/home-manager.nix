{ config, lib, pkgs, ... }:

let sources = import ../../nix/sources.nix; in {
  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  home.packages = [
    pkgs.bat
    pkgs.firefox
    pkgs.fzf
    pkgs.git-crypt
    pkgs.htop
    pkgs.gtop
    pkgs.jq
    pkgs.ripgrep
    pkgs.rofi
    pkgs.tree
    pkgs.watch
    pkgs.zathura
    pkgs._1password

    pkgs.go
    pkgs.gopls
    pkgs.zig-master

    pkgs.tlaplusToolbox
    pkgs.tetex

    pkgs.nodejs-14_x
    pkgs.yarn
    #pkgs.vscode
    pkgs.vscode-fhs
    pkgs.vscode-extensions.ms-vscode-remote.remote-ssh   #Fixing remote-ssh

    pkgs.kubectl
    pkgs.minikube
    pkgs.kustomize
    pkgs.kubernetes-helm
    
    # cluster management tool
    pkgs.k9s
    pkgs.lens
    pkgs.krew
    # pkgs.kubecolor #TODO unstable
    
    pkgs.kind                # kubernetes in docker

  ];

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = {
    LANG = "en_GB.UTF-8";
    LC_CTYPE = "en_GB.UTF-8";
    LC_ALL = "en_GB.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "sh -c 'col -bx | ${pkgs.bat}/bin/bat -l man -p'";
  };

  home.file.".inputrc".source = ./inputrc;

  xdg.configFile."i3/config".text = builtins.readFile ./i3;
  xdg.configFile."rofi/config.rasi".text = builtins.readFile ./rofi;

  # tree-sitter parsers
  xdg.configFile."nvim/parser/proto.so".source = "${pkgs.tree-sitter-proto}/parser";
  xdg.configFile."nvim/queries/proto/folds.scm".source =
    "${sources.tree-sitter-proto}/queries/folds.scm";
  xdg.configFile."nvim/queries/proto/highlights.scm".source =
    "${sources.tree-sitter-proto}/queries/highlights.scm";
  xdg.configFile."nvim/queries/proto/textobjects.scm".source =
    ./textobjects.scm;

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.gpg.enable = true;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ./bashrc;

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
    };
  };

  programs.direnv= {
    enable = true;

    config = {
      whitelist = {
        prefix= [
          "$HOME/code/go/src/github.com/hashicorp"
          "$HOME/code/go/src/github.com/zerodeth"
        ];

        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" [
      "source ${sources.theme-bobthefish}/fish_prompt.fish"
      "source ${sources.theme-bobthefish}/fish_right_prompt.fish"
      "source ${sources.theme-bobthefish}/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]);

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdiff = "git diff";
      gl = "git prettylog";
      gp = "git push";
      gs = "git status";
      gt = "git tag";
      
      "..." = "cd ../..";

      # Two decades of using a Mac has made this such a strong memory
      # that I'm just going to keep it consistent.
      pbcopy = "xclip";
      pbpaste = "xclip -o";
    };

    plugins = map (n: {
      name = n;
      src  = sources.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };

  programs.git = {
    enable = true;
    userName = "Sherif Abdalla";
    userEmail = "sherif@abdalla.uk";
    signing = {
      key = "FDA619F16BBFA377";
      signByDefault = true;
    };
    aliases = {
      prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
      root = "rev-parse --show-toplevel";
    };
    extraConfig = {
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      credential.helper = "store"; # want to make this more secure
      github.user = "zerodeth";
      push.default = "tracking";
      init.defaultBranch = "main";
    };
  };

  programs.go = {
    enable = true;
    goPath = "code/go";
    goPrivate = [ "github.com/mitchellh" "github.com/hashicorp" "rfc822.mx" ];
  };

  programs.tmux = {
    enable = true;
    terminal = "xterm-256color";
    shortcut = "l";
    secureSocket = false;

    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"

      set -g @dracula-show-battery false
      set -g @dracula-show-network false
      set -g @dracula-show-weather false

      bind -n C-k send-keys "clear"\; send-keys "Enter"

      run-shell ${sources.tmux-pain-control}/pain_control.tmux
      run-shell ${sources.tmux-dracula}/dracula.tmux
    '';
  };

  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      key_bindings = [
        { key = "K"; mods = "Command"; chars = "ClearHistory"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
        { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Subtract"; mods = "Command"; action = "DecreaseFontSize"; }
      ];
    };
  };

  programs.kitty = {
    enable = true;
    extraConfig = builtins.readFile ./kitty;
  };

  programs.i3status = {
    enable = true;

    general = {
      colors = true;
      color_good = "#8C9440";
      color_bad = "#A54242";
      color_degraded = "#DE935F";
    };

    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
    };
  };

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-nightly;

    plugins = with pkgs; [
      customVim.vim-cue
      customVim.vim-fish
      customVim.vim-fugitive
      customVim.vim-misc
      customVim.vim-pgsql
      customVim.vim-tla
      customVim.vim-zig
      customVim.pigeon
      customVim.AfterColors

      customVim.vim-nord
      customVim.nvim-lspconfig
      customVim.nvim-treesitter
      customVim.nvim-treesitter-playground
      customVim.nvim-treesitter-textobjects

      vimPlugins.ctrlp
      vimPlugins.vim-airline
      vimPlugins.vim-airline-themes
      vimPlugins.vim-eunuch
      vimPlugins.vim-gitgutter

      vimPlugins.vim-markdown
      vimPlugins.vim-nix
      vimPlugins.typescript-vim
    ];

    extraConfig = (import ./vim-config.nix) { inherit sources; };
  };

  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "tty";

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  # Make cursor not tiny on HiDPI screens
  xsession.pointerCursor = {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

  programs.htop = {
    enable = true;

    settings = {
      # header_margin = false;
      # hideKernelThreads = true;
      # hideThreads = true;
      # hideUserlandThreads = true;
      # sortKey = "PERCENT_CPU";
      # left_meters = [ "LeftCPUs2" "Memory" "Swap" "Hostname" ];
      # right_meters = [ "RightCPUs2" "Tasks" "LoadAverage" "Uptime" ];
      # left_meters = [ "LeftCPUs2" "Memory" "CPU" ];
      # right_meters = [ "RightCPUs2" "Tasks" "LoadAverage" "Uptime" ];

      fields = [ 50 0 48 17 18 38 39 40 2 46 47 49 1 ];
      sort_key = 111;
      sort_direction = 1;
      hide_threads = 1;
      hide_kernel_threads = 1;
      hide_userland_threads = 1;
      shadow_other_users = 0;
      show_thread_names = 0;
      show_program_path = 1;
      highlight_base_name = 0;
      highlight_megabytes = 0;
      highlight_threads = 0;
      tree_view = 1;
      header_margin = 1;
      detailed_cpu_time = 1;
      cpu_count_from_zero = 1;
      update_process_names = 0;
      account_guest_in_cpu_meter = 0;
      color_scheme = 6;
      delay = 15;
      left_meters = [ "CPU" "AllCPUs" ];
      left_meter_modes = [ 2 1 ];
      right_meters = [ "Blank" "Clock" "Uptime" "LoadAverage" "Tasks" "Swap" "Memory" ];
      right_meter_modes = [ 2 2 2 2 2 2 2 ];
    };
  };

}
