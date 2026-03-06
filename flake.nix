{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Master nixpkgs is used for really bleeding edge packages. Warning
    # that this is extremely unstable and shouldn't be relied on. Its
    # mostly for testing.
    nixpkgs-master.url = "github:nixos/nixpkgs";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other packages
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri - scrollable-tiling Wayland compositor
    niri.url = "github:sodiboo/niri-flake";
    niri-scratchpad.url = "github:argosnothing/niri-scratchpad-rs";
    # niri-deep = {
    #   url = "/home/m/Projects/niri-deep";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # LLM agents for Nix
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Python/uv packaging toolchain (used for APM and other uv-based Python tools)
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LazyVim Nix (declarative Neovim + LazyVim)
    lazyvim.url = "github:pfassina/lazyvim-nix";

    # Non-flake sources for packages we build ourselves
    agent-of-empires-src.url = "github:njbrake/agent-of-empires";
    uniclip-src = { url = "github:quackduck/uniclip"; flake = false; };
    tmux-menus-src = { url = "github:jaclu/tmux-menus"; flake = false; };
    aw-import-screentime-src = { url = "github:ActivityWatch/aw-import-screentime/8d6bf4a84bac840c8af577652ee70514ef3e6bc1"; flake = false; };

    # Mango window control for Wayland
    mangowc = {
      url = "github:DreamMaoMao/mangowc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia shell for Wayland
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative git repo management
    git-repo-manager = {
      url = "github:hakoerber/git-repo-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sopsidy = {
      url = "github:timewave-computer/sopsidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Doom Emacs via nix-doom-emacs-unstraightened (builds Doom + deps with Nix)
    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      # Don't pull in its nixpkgs — neither the module nor overlay uses it
      inputs.nixpkgs.follows = "";
    };

  };

  outputs = { self, nixpkgs, home-manager, lazyvim, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.rust-overlay.overlays.default
      inputs.niri.overlays.niri
      # inputs.niri-deep.overlays.default
      inputs.llm-agents.overlays.default
      inputs.git-repo-manager.overlays.git-repo-manager

      # Build non-flake packages from source
      (final: prev: {
        agent-of-empires = inputs.agent-of-empires-src.packages.${prev.system}.default;

        apm =
          let
            src = final.fetchFromGitHub {
              owner = "microsoft";
              repo = "apm";
              rev = "v0.7.3";
              hash = "sha256-B2gAGZpziIf5L7Unc+ojJlCKk8O7qWUnTYmtNFLsxKk=";
            };
            workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };
            overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
            # Fix upstream bug: get_auto_integrate / set_auto_integrate are called
            # in cli.py but missing from config.py (v0.7.3).
            pyprojectOverrides = _final: prev: {
              apm-cli = prev.apm-cli.overrideAttrs (old: {
                postInstall = (old.postInstall or "") + ''
                  cfg=$(find $out -path "*/apm_cli/config.py" | head -1)
                  cat >> "$cfg" << 'PYEOF'


def get_auto_integrate():
    return get_config().get("auto_integrate", True)


def set_auto_integrate(value: bool):
    update_config({"auto_integrate": value})
PYEOF
                '';
              });
            };
            pythonSet = (final.callPackage inputs.pyproject-nix.build.packages {
              python = final.python3;
            }).overrideScope (final.lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
            ]);
          in
          pythonSet.mkVirtualEnv "apm" workspace.deps.default;

        uniclip = final.buildGoModule {
          pname = "uniclip";
          version = "0-unstable";
          src = inputs.uniclip-src;
          vendorHash = "sha256-ugrWrB0YVs/oWAR3TC3bEpt1VXQC1c3oLrvFJxlR8pw=";
          patches = [ ./patches/uniclip-bind-and-env-password.patch ];
          meta.description = "Universal clipboard - copy on one device, paste on another";
        };

        wayprompt = prev.wayprompt.overrideAttrs (old: {
          patches = (old.patches or []) ++ [ ./patches/wayprompt-wayland-clipboard-paste.patch ];
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.makeWrapper ];
          postFixup = (old.postFixup or "") + ''
            wrapProgram $out/bin/wayprompt --prefix PATH : ${final.wl-clipboard}/bin
            wrapProgram $out/bin/pinentry-wayprompt --prefix PATH : ${final.wl-clipboard}/bin
          '';
        });

        tmuxPlugins = prev.tmuxPlugins // {
          "tmux-menus" = final.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-menus";
            version = "0-unstable-2026-02-21";
            src = inputs.tmux-menus-src;
            rtpFilePath = "menus.tmux";
          };
        };

        dotagents = final.stdenv.mkDerivation (finalAttrs: {
          pname = "dotagents";
          version = "0.15.0";

          src = final.fetchFromGitHub {
            owner = "getsentry";
            repo = "dotagents";
            rev = finalAttrs.version;
            hash = "sha256-uqS2hh61urEtZ+ZLzyzdNChNA8kNNMemZUrV510uCfk=";
          };

          pnpmDeps = final.pnpm.fetchDeps {
            inherit (finalAttrs) pname version src;
            fetcherVersion = 1; # pnpm-lock.yaml lockfileVersion 9.0
            hash = "sha256-E2YJ2bw9OB3T1//2rtHx0dqgoYFKo4Cj59x13QdJj4s=";
          };

          nativeBuildInputs = [ final.pnpm.configHook final.nodejs_22 final.makeWrapper ];

          buildPhase = ''
            runHook preBuild
            pnpm build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            pnpm install --frozen-lockfile --prod
            mkdir -p $out/lib/node_modules/@sentry/dotagents
            cp -r dist package.json node_modules $out/lib/node_modules/@sentry/dotagents/
            mkdir -p $out/bin
            makeWrapper ${final.nodejs_22}/bin/node $out/bin/dotagents \
              --add-flags "$out/lib/node_modules/@sentry/dotagents/dist/cli/index.js"
            runHook postInstall
          '';

          meta = with final.lib; {
            description = "Package manager for AI agent skill dependencies";
            homepage = "https://github.com/getsentry/dotagents";
            license = licenses.mit;
            mainProgram = "dotagents";
            platforms = platforms.all;
          };
        });

        opencode-dev =
          let
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = prev.system;
              config.allowUnfree = true;
            };
            src = builtins.fetchTarball {
              url = "https://github.com/anomalyco/opencode/archive/0a74fcd65dcceb1315d9e2580b97fa970f8bd154.tar.gz";
              sha256 = "0zk9m1xcy5nd9p55h9fyr0r5s9m47lpzwb2h7xkxirrxfd41gknw";
            };
            node_modules = final.callPackage (src + "/nix/node_modules.nix") {
              rev = "pr-13485";
              bun = pkgs-unstable.bun;
            };
          in
          final.callPackage (src + "/nix/opencode.nix") {
            inherit node_modules;
            bun = pkgs-unstable.bun;
          };
      })

      (final: prev:
        let
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = prev.system;
            config.allowUnfree = true;
          };
        in rec {
        # gh CLI on stable has bugs.
        # gh = pkgs-unstable.gh;

        # Want the latest version of these
        # claude-code = pkgs-unstable.claude-code;
        wezterm = pkgs-unstable.wezterm;

      })
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "m";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "m";
      wsl    = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
      system = "aarch64-darwin";
      user   = "m";
      darwin = true;
    };

    # Sopsidy secret collector script (rbw/bitwarden backend)
    # Built for common host systems since collect-secrets runs locally,
    # not on the target VM.
    packages.aarch64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.x86_64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "x86_64-darwin"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.aarch64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "aarch64-linux"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.x86_64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
  };
}
