# den/aspects/features/shell-git.nix
#
# Shell and git configuration slice for user m.
#
# Migrated from the legacy Home Manager entrypoint (Task 4 of den migration).
# Covers: zsh, bash, inputrc, session variables, session path, manpager,
#         direnv, zoxide, atuin, oh-my-posh, gh CLI, git (non-signing),
#         packages: tig, git-credential-github (Linux non-WSL),
#         and Linux-only zsh shell wrappers + VMware filemode hook.
#
# Signing / GPG / gpg-agent / rbw are intentionally NOT here.
{ den, lib, ... }: {

  den.aspects.shell-git = {
    includes = [
      # Parametric include: captures {host} from den context so the homeManager
      # module can close over isDarwin / isLinux / isWSL at eval time.
      ({ host, ... }:
        let
          isDarwin      = host.class == "darwin";
          isLinux       = host.class == "nixos";
          isWSL         = host.wsl.enable or false;
          isNonWSLLinux = isLinux && !isWSL;
          isVM          = host.vmware.enable or false;  # VMware shared-folder host
          defaultGeneratedDir =
            if isVM then
              "/nixos-generated"
            else
              "$HOME/.local/share/nix-config-generated";
          generatedDirSetup = ''
            generated_dir="''${GENERATED_INPUT_DIR-}"
            if [ -z "$generated_dir" ]; then
              generated_dir="${defaultGeneratedDir}"
            fi
          '';
          yeetAndYoinkDirSetup = ''
            yeet_and_yoink_dir="''${YEET_AND_YOINK_INPUT_DIR-}"
            if [ -z "$yeet_and_yoink_dir" ]; then
              yeet_and_yoink_dir="/Users/m/Projects/yeet-and-yoink"
            fi
          '';
        in {
          homeManager = { pkgs, lib, ... }:
            let
              # ---------------------------------------------------------------
              # Aliases — shared across zsh and bash
              # ---------------------------------------------------------------
              shellAliases = {
                g     = "git";
                gs    = "git status";
                ga    = "git add";
                gc    = "git commit";
                gl    = "git prettylog";
                gp    = "git push";
                gco   = "git checkout";
                gcp   = "git cherry-pick";
                gdiff = "git diff";

                l   = "ls";
                lah = "eza -alh --color=auto --group-directories-first --icons";
                la  = "eza -la";
                ll  = "eza -lh --color=auto --group-directories-first --icons";
                magit        = "emacsclient -a \"\" -nw -e -q '(progn (magit-status))'";
                "nix-gc"           = "nix-collect-garbage -d";
                "nix-update-flakes" = "nix flake update";

                # cc = "claude";
                oc  = "opencode";
                ocd = "opencode-dev";
                openspec-in-progress = "openspec list --json | jq -r '.changes[] | select(.status == \"in-progress\").name'";

                rs     = "cargo";
                kubectl = "kubecolor";

                nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";
              } // (lib.optionalAttrs isLinux {
                pbcopy  = "wl-copy --type text/plain";
                pbpaste = "wl-paste --type text/plain";
                open    = "xdg-open";
                noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
                nix-config = "nvim /nix-config";
                niks = "${generatedDirSetup}; ${yeetAndYoinkDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" YEET_AND_YOINK_INPUT_DIR=\"$yeet_and_yoink_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
                nikt = "${generatedDirSetup}; ${yeetAndYoinkDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" YEET_AND_YOINK_INPUT_DIR=\"$yeet_and_yoink_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
              }) // (lib.optionalAttrs isDarwin {
                nix-config = "nvim ~/.config/nix-config";
                niks = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                nikt = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                pinentry = "pinentry-mac";
              });

              # ---------------------------------------------------------------
              # manpager helper — wraps bat for man page rendering
              # https://github.com/sharkdp/bat/issues/1145
              # ---------------------------------------------------------------
              manpager = pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
                sh -c 'col -bx | bat -l man -p'
              '' else ''
                cat "$1" | col -bx | bat --language man --style plain
              '');

            in {
              # ---------------------------------------------------------------
              # Home Manager base settings
              # ---------------------------------------------------------------
              home.stateVersion = "18.09";
              home.enableNixpkgsReleaseCheck = false;
              xdg.enable = true;

              # ---------------------------------------------------------------
              # Dotfiles
              # ---------------------------------------------------------------
              home.file.".inputrc".source = ../../../dotfiles/common/inputrc;

              # ---------------------------------------------------------------
              # Session variables
              # ---------------------------------------------------------------
              home.sessionVariables = {
                LANG     = "en_US.UTF-8";
                LC_CTYPE = "en_US.UTF-8";
                LC_ALL   = "en_US.UTF-8";
                EDITOR   = "nvim";
                PAGER    = "less -FirSwX";
                MANPAGER = "${manpager}/bin/manpager";
              } // (lib.optionalAttrs isDarwin {
                # See: https://github.com/NixOS/nixpkgs/issues/390751
                DISPLAY = "nixpkgs-390751";
              });

              # ---------------------------------------------------------------
              # Session PATH (Darwin only)
              # ---------------------------------------------------------------
              home.sessionPath = lib.optionals isDarwin [
                "/Applications/VMware Fusion.app/Contents/Library"
                "/Users/m/.cargo/bin"
              ];

              # ---------------------------------------------------------------
              # Packages (shell/git slice only)
              # ---------------------------------------------------------------
              home.packages = [
                pkgs.bat
                pkgs.eza
                pkgs.fd
                pkgs.fnm
                pkgs.fzf
                pkgs.jq
                pkgs.kubecolor
                pkgs.kubectl
                pkgs.rbw
                pkgs.ripgrep
                pkgs.tig
                manpager
              ] ++ (lib.optionals isNonWSLLinux [
                # Custom git credential helper: wraps rbw for github.com entries
                # (rbw's built-in git-credential-rbw expects entry named by hostname)
                (pkgs.writeShellScriptBin "git-credential-github" ''
                  case "$1" in
                    get)
                      while IFS='=' read -r key value; do
                        [ -z "$key" ] && break
                        case "$key" in host) host="$value" ;; esac
                      done
                      case "$host" in
                        github.com|gist.github.com)
                          token=$(${pkgs.rbw}/bin/rbw get github-token 2>/dev/null)
                          [ -n "$token" ] && printf 'protocol=https\nhost=%s\nusername=smallstepman\npassword=%s\n' "$host" "$token"
                          ;;
                      esac
                      ;;
                  esac
                '')
              ]);

              # ---------------------------------------------------------------
              # Zsh
              # ---------------------------------------------------------------
              programs.zsh = {
                enable = true;
                autosuggestion.enable = true;
                syntaxHighlighting.enable = true;
                shellAliases = shellAliases;
                initContent = ''
                  # VSCode shell integration
                  [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

                  # fnm (Node version manager)
                  eval "$(fnm env --use-on-cd)"
                  bindkey -v
                  source ${../../../dotfiles/common/zsh-manydot.sh}

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
                '' + (lib.optionalString isDarwin ''

                  # Homebrew
                  eval "$(/opt/homebrew/bin/brew shellenv)"

                  # NixOS VM management
                  vm() { ~/.config/nix/docs/vm.sh "$@"; }
                '') + (lib.optionalString isLinux ''

                  # gh: inject GITHUB_TOKEN per-invocation from rbw (no global env var)
                  gh() { GITHUB_TOKEN=$(rbw get github-token) command gh "$@"; }

                  # Ad-hoc API key injection (usage: with-openai some-command --flag)
                  with-openai() { OPENAI_API_KEY=$(rbw get openai-api-key) "$@"; }
                  with-amp() { AMP_API_KEY=$(rbw get amp-api-key) "$@"; }
                  copilot() { COPILOT_GITHUB_TOKEN=$(rbw get github-token) command copilot "$@"; }
                  claude() { CLAUDE_CODE_OAUTH_TOKEN=$(rbw get claude-oauth-token) command claude "$@"; }
                  codex() { OPENAI_API_KEY=$(rbw get openai-api-key) command codex "$@"; }
                '') + (lib.optionalString isVM ''

                  # Auto-fix fileMode for git repos on VMware shared folders
                  # (macOS reports all files as 755; git sees mode changes vs index)
                  # Only runs once per repo per shell session (caches in associative array)
                  typeset -gA _git_filemode_fixed
                  _fix_git_filemode() {
                    if [[ "$PWD" == /Users/m/Projects/* ]] && [[ -d .git ]]; then
                      local root=$(git rev-parse --show-toplevel 2>/dev/null)
                      [[ -z "$root" ]] && return
                      [[ -n "''${_git_filemode_fixed[$root]}" ]] && return
                      git config core.fileMode false 2>/dev/null
                      git submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null
                      _git_filemode_fixed[$root]=1
                    fi
                  }
                  add-zsh-hook chpwd _fix_git_filemode
                  _fix_git_filemode  # run once on shell init
                '');
              };

              # ---------------------------------------------------------------
              # Bash
              # ---------------------------------------------------------------
              programs.bash = {
                enable = true;
                shellOptions = [];
                historyControl = [ "ignoredups" "ignorespace" ];
                initExtra = builtins.readFile ../../../dotfiles/common/bashrc;
                shellAliases = shellAliases;
              };

              # ---------------------------------------------------------------
              # Direnv
              # ---------------------------------------------------------------
              programs.direnv = {
                enable = true;
                config = {
                  whitelist = {
                    prefix = [
                      "$HOME/code/go/src/github.com/hashicorp"
                      "$HOME/code/go/src/github.com/smallstepman"
                    ];
                    exact = [ "$HOME/.envrc" ];
                  };
                };
              };

              # ---------------------------------------------------------------
              # Zoxide
              # ---------------------------------------------------------------
              programs.zoxide = {
                enable = true;
                enableBashIntegration = true;
                enableZshIntegration = true;
              };

              # ---------------------------------------------------------------
              # Atuin (shell history)
              # ---------------------------------------------------------------
              programs.atuin = {
                enable = true;
              };

              # ---------------------------------------------------------------
              # Oh My Posh (shell prompt)
              # ---------------------------------------------------------------
              programs.oh-my-posh = {
                enable = true;
                settings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/oh-my-posh.json);
              };

              # ---------------------------------------------------------------
              # gh CLI
              # Darwin: use gh's native credential helper (Touch ID backed)
              # Linux:  disabled — credential helper is the rbw-based git-credential-github
              # ---------------------------------------------------------------
              programs.gh = {
                enable = true;
                gitCredentialHelper.enable = isDarwin;
              };

              # ---------------------------------------------------------------
              # Git (non-signing behavior only)
              # Signing key, signing.signByDefault, gpg.program, services.gpg-agent
              # are intentionally excluded — they remain in home-manager.nix
              # until the GPG/signing task.
              # ---------------------------------------------------------------
              programs.git = {
                enable = true;
                settings = {
                  user.name   = "Marcin Nowak Liebiediew";
                  user.email  = "m.liebiediew@gmail.com";
                  branch.autosetuprebase = "always";
                  color.ui   = true;
                  core.askPass        = ""; # empty = use terminal for password prompts
                  core.fileMode       = !isLinux; # VMware shared folders force 755 on all files
                  core.untrackedCache = true;
                  github.user         = "smallstepman";
                  push.default        = "tracking";
                  init.defaultBranch  = "main";
                  aliases = {
                    cleanup   = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
                    prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
                    root      = "rev-parse --show-toplevel";
                    ce        = "git commit --amend --no-edit";
                  };
                } // (lib.optionalAttrs isLinux {
                  # Linux: custom credential helper reads GitHub token from rbw
                  "credential \"https://github.com\"".helper  = "github";
                  "credential \"https://gist.github.com\"".helper = "github";
                });
              };
            };
        })
    ];
  };

}
