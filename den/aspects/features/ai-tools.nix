# den/aspects/features/ai-tools.nix
#
# AI tooling and coding-agent configuration aspect for user m.
#
# Migrated from the legacy Home Manager entrypoint (Task 6 of den migration).
# Covers: llm-agents package set, opencode HM module, opencodeAwesome config,
#         opencode XDG config files, ensureOpencodePackageJsonWritable activation,
#         and programs.opencode.
#
# WSL is threaded from the den host context (host.wsl.enable or false) rather
# than the legacy top-level isWSL arg.
{ den, lib, inputs, ... }: {

  den.aspects.ai-tools = {
    includes = [
      ({ host, ... }:
        let
          isWSL = host.wsl.enable or false;
        in {
          homeManager = { pkgs, lib, ... }:
            let
              opencodeAwesome = import ../../../dotfiles/common/opencode/awesome.nix { inherit pkgs lib; };
            in {
              imports = [
                (import ../../../dotfiles/common/opencode/modules/home-manager.nix { inherit isWSL; })
              ];

              # ---------------------------------------------------------------
              # Packages — AI tools
              # ---------------------------------------------------------------
              home.packages = [
                pkgs.agent-of-empires  # terminal session manager for AI agents
                pkgs.gastown           # gt - Gas Town multi-agent orchestration system

                # coding agents
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

                # workflow & project management
                pkgs.llm-agents.beads         # bd — Beads CLI
                pkgs.llm-agents.beads-rust    # br - Beads CLI but faster (Rust)
                pkgs.llm-agents.beads-viewer  # bv — graph-aware TUI for Beads issue tracker
                pkgs.llm-agents.openspec
                pkgs.llm-agents.workmux

                # .agents & AGENTS.md management
                pkgs.dotagents
                pkgs.apm

                # utilities
                pkgs.llm-agents.copilot-language-server
                pkgs.llm-agents.openskills
              ];

              # ---------------------------------------------------------------
              # XDG config files
              # ---------------------------------------------------------------
              xdg.configFile."opencode/plugins/superpowers.js".source =
                opencodeAwesome.superpowersPlugin;
              xdg.configFile."opencode/skills/superpowers" = {
                source = opencodeAwesome.superpowersSkillsDir;
                recursive = true;
              };

              # ---------------------------------------------------------------
              # Activation hooks
              # ---------------------------------------------------------------

              # Keep package.json writable so opencode can update/install plugin deps at runtime.
              home.activation.ensureOpencodePackageJsonWritable =
                lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  run mkdir -p "$HOME/.config/opencode"
                  packageJson="$HOME/.config/opencode/package.json"
                  if [ -L "$packageJson" ]; then
                    run rm -f "$packageJson"
                  fi
                  run cp ${../../../dotfiles/common/opencode/package.json} "$packageJson"
                  run chmod u+w "$packageJson"
                '';

              # ---------------------------------------------------------------
              # OpenCode
              # ---------------------------------------------------------------
              programs.opencode = {
                enable = true;
                package = pkgs.llm-agents.opencode;
                settings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/opencode/settings.json);
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

            };
        })
    ];
  };

}
