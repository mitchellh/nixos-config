{ inputs }:
let
  nixpkgs = inputs.nixpkgs;

  # Overlays is the list of overlays we want to apply from flake inputs.
  overlays = [
    inputs.rust-overlay.overlays.default
    inputs.niri.overlays.niri
    # inputs.niri-deep.overlays.default
    inputs.llm-agents.overlays.default
    inputs.git-repo-manager.overlays.git-repo-manager

    # Build non-flake packages from source
    (final: prev: {
      agent-of-empires = inputs.agent-of-empires-src.packages.${prev.stdenv.hostPlatform.system}.default;
      gastown = inputs.gastown.packages.${prev.stdenv.hostPlatform.system}.gt.overrideAttrs (old: {
        vendorHash = "sha256-fZucwy6omCXV5/ebOzcqOgJ4SfouCHasmstEX2na5SQ=";
      });

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
        patches = [ ../patches/uniclip-bind-and-env-password.patch ];
        meta.description = "Universal clipboard - copy on one device, paste on another";
      };

      wayprompt = prev.wayprompt.overrideAttrs (old: {
        patches = (old.patches or []) ++ [ ../patches/wayprompt-wayland-clipboard-paste.patch ];
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
            system = prev.stdenv.hostPlatform.system;
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
          system = prev.stdenv.hostPlatform.system;
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

  generated =
    let
      requireFile = relative:
        let
          path =
            if inputs.generated == null then
              null
            else
              inputs.generated + "/${relative}";
        in
          if path != null && builtins.pathExists path then
            path
          else
            throw ''
              Missing generated input file `${relative}`.
              Create a wrapper flake with `scripts/external-input-flake.sh`
              or call `lib.mkOutputs { generated = <path>; }`.
              Supported default locations are `~/.local/share/nix-config-generated` on macOS
              and `/nixos-generated` inside the VMware guest.
            '';
    in {
      root = inputs.generated;
      inherit requireFile;
      readFile = relative: builtins.readFile (requireFile relative);
    };

  yeetAndYoink =
    let
      requirePath = relative:
        let
          path =
            if inputs.yeetAndYoink == null then
              null
            else
              inputs.yeetAndYoink + "/${relative}";
        in
          if path != null && builtins.pathExists path then
            path
          else
            throw ''
              Missing yeet-and-yoink input path `${relative}`.
              Create a wrapper flake with `scripts/external-input-flake.sh`
              or call `lib.mkOutputs { yeetAndYoink = <path>; }`.
              Supported default location is `/Users/m/Projects/yeet-and-yoink`.
            '';
    in {
      root = inputs.yeetAndYoink;
      inherit requirePath;
    };

  den = (nixpkgs.lib.evalModules {
    modules = [ ./default.nix ./hosts.nix (inputs.import-tree ./aspects) ];
    specialArgs = { inherit generated inputs overlays yeetAndYoink; };
  }).config;
in {
  inherit (den.flake) nixosConfigurations darwinConfigurations;

  # Sopsidy secret collector script (rbw/bitwarden backend)
  # Built for common host systems since collect-secrets runs locally,
  # not on the target VM.
  packages.aarch64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "aarch64-darwin"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.x86_64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "x86_64-darwin"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.aarch64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "aarch64-linux"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.x86_64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
}
