{ pkgs, lib }:

let
  fetchGitHubTarball = { owner, repo, rev, sha256 }:
    builtins.fetchTarball {
      url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
      inherit sha256;
    };

  src = {
    kdcoBackgroundAgents = fetchGitHubTarball {
      owner = "kdcokenny";
      repo = "opencode-background-agents";
      rev = "e1ada2dbe9c4a5f03b44b4bbcb964b44f0247483";
      sha256 = "19zvfy1lzlajqiisnlsjjn39j3zl4lw7kbhz5kz9zq577c3i4lqs";
    };
    kdcoNotify = fetchGitHubTarball {
      owner = "kdcokenny";
      repo = "opencode-notify";
      rev = "fe2bba68a3c2a82c727af69db5923f628aa9caa4";
      sha256 = "06zzilb6c8k870pl6lyg2wzvjsl1zvwvq25307i4zl4c1q5mws4a";
    };
    kdcoWorkspace = fetchGitHubTarball {
      owner = "kdcokenny";
      repo = "opencode-workspace";
      rev = "aa019b01bbdd7ee46618cede005667114bf6cf3d";
      sha256 = "06zbzjfl5siivyylb03ba4gdl0f6y271bvrhl727qq8fl09q32mq";
    };
    kdcoWorktree = fetchGitHubTarball {
      owner = "kdcokenny";
      repo = "opencode-worktree";
      rev = "475a7386e98accdb87e8b0c3c63b93b98407786f";
      sha256 = "1v6g8xz9ihwn1pf6f58fi5sgkpsafxgn1qim02n54bc4cyn4zslv";
    };
    ayuTheme = fetchGitHubTarball {
      owner = "postrednik";
      repo = "opencode-ayu-theme";
      rev = "71c2a8b2fd0adcc59c0db3c5e793213a8bd54ccc";
      sha256 = "089v7dy7sgbz2zcv5f953g3503kikpc1lpvznpkd32qhkl3hv9aq";
    };
    poimandresTheme = fetchGitHubTarball {
      owner = "ajaxdude";
      repo = "opencode-ai-poimandres-theme";
      rev = "f87ba503439b012fe495092104a51ef4163c8b19";
      sha256 = "16qq6s725x7vhv491g15qjszf87bcp3f7mrgq149hy2m6s09qp3y";
    };
    agentic = fetchGitHubTarball {
      owner = "Cluster444";
      repo = "agentic";
      rev = "3a3915310d3d03d4a45114b7b0c0a17c34bf0e8b";
      sha256 = "1ih7qrsaxpqznqkcgjzmgql65z2pmmxzb957pamgxr8hp5c2lkmp";
    };
    opencodeAgents = fetchGitHubTarball {
      owner = "darrenhinde";
      repo = "opencode-agents";
      rev = "6efa2dc910807312ef4337284912bd20e2c2b209";
      sha256 = "0vknvlaajh5h7n779kxy3di62rd3hhjs994ihmkkdh6mlamgzhhl";
    };
    redstone = fetchGitHubTarball {
      owner = "BackGwa";
      repo = "Redstone";
      rev = "8cf355048405598719232c05465910b6404a5828";
      sha256 = "0g6zf2c7g8gzxcgp25nmfxvv0rlviwcdl4rgw7iwhwggxk83zqh0";
    };
    voltagentSubagents = fetchGitHubTarball {
      owner = "VoltAgent";
      repo = "awesome-claude-code-subagents";
      rev = "f0f9aba02d31a8ed53331b85379adf7bc8f9719a";
      sha256 = "1d9kn7dkc675j90jjgfxk3jfmf4jkmmrk3526i0y80fypx68zpxk";
    };
    morphFastApply = fetchGitHubTarball {
      owner = "JRedeker";
      repo = "opencode-morph-fast-apply";
      rev = "4ba0d8f12417a9cf9b23a1fde62b47f4e1d18e1e";
      sha256 = "1pdcpmnr0srqi2d2c8i4c9a984d7ph169xlwg5yr1491ghx7ak6h";
    };
    superpowers = fetchGitHubTarball {
      owner = "obra";
      repo = "superpowers";
      rev = "a0b9ecce2b25aa7d703138f17650540c2e8b2cde";
      sha256 = "1r4sj0pz25885sxv6cvcv5ndjszq8zhriasvi16h8sni0ssampc3";
    };
  };

  sanitize = name:
    lib.replaceStrings
      [ "/" " " ":" "." "(" ")" "[" "]" "'" "\"" ]
      [ "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" ]
      name;

  mkPrefixedFileAttrs =
    {
      prefix,
      dir,
      suffix,
    }:
    let
      files = lib.filter (file: lib.hasSuffix suffix (toString file)) (lib.filesystem.listFilesRecursive dir);
    in
    builtins.listToAttrs (
      map (
        file:
        let
          fileStr = toString file;
          dirStr = toString dir;
          rel = lib.removePrefix "${dirStr}/" fileStr;
          noSuffix = lib.removeSuffix suffix rel;
        in
        {
          name = builtins.unsafeDiscardStringContext (sanitize "${prefix}-${noSuffix}");
          value = file;
        }
      ) files
    );

  agents = lib.foldl' lib.recursiveUpdate { } [
    (mkPrefixedFileAttrs {
      prefix = "agentic";
      dir = src.agentic + "/agent";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "kdco-workspace";
      dir = src.kdcoWorkspace + "/src/agent";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "redstone";
      dir = src.redstone + "/agents";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "opencode-agents";
      dir = src.opencodeAgents + "/.opencode/agent";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "voltagent";
      dir = src.voltagentSubagents + "/categories";
      suffix = ".md";
    })
  ];

  commands = lib.foldl' lib.recursiveUpdate { } [
    (mkPrefixedFileAttrs {
      prefix = "agentic";
      dir = src.agentic + "/command";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "agentic";
      dir = src.agentic + "/.opencode/command";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "kdco-workspace";
      dir = src.kdcoWorkspace + "/src/command";
      suffix = ".md";
    })
    (mkPrefixedFileAttrs {
      prefix = "opencode-agents";
      dir = src.opencodeAgents + "/.opencode/command";
      suffix = ".md";
    })
  ];

  themes = {
    ayu-dark = builtins.fromJSON (builtins.readFile "${src.ayuTheme}/.opencode/themes/ayu-dark.json");
    poimandres = builtins.fromJSON (builtins.readFile "${src.poimandresTheme}/.opencode/themes/poimandres.json");
    poimandres-accessible = builtins.fromJSON (
      builtins.readFile "${src.poimandresTheme}/.opencode/themes/poimandres-accessible.json"
    );
    poimandres-turquoise-expanded = builtins.fromJSON (
      builtins.readFile "${src.poimandresTheme}/.opencode/themes/poimandres-turquoise-expanded.json"
    );
  };

  runtimeAssets = pkgs.runCommand "opencode-awesome-runtime-assets" { } ''
    set -eu
    mkdir -p "$out"/{skill,tool,plugins}

    sanitize() {
      echo "$1" | sed -e 's|/|-|g' -e 's|[^A-Za-z0-9._-]|-|g'
    }

    copy_skill_dirs() {
      src_dir="$1"
      prefix="$2"
      dest_dir="$3"
      [ -d "$src_dir" ] || return 0

      find "$src_dir" -type f -name 'SKILL.md' | while IFS= read -r file; do
        skill_dir="$(dirname "$file")"
        rel="''${skill_dir#"$src_dir"/}"
        name="$(sanitize "$prefix-''${rel}")"
        if [ -e "$dest_dir/$name/SKILL.md" ]; then
          continue
        fi
        mkdir -p "$dest_dir/$name"
        cp -R "$skill_dir"/. "$dest_dir/$name/"
      done
    }

    copy_tool_flat() {
      src_dir="$1"
      prefix="$2"
      dest_dir="$3"
      [ -d "$src_dir" ] || return 0

      find "$src_dir" -type f \( -name '*.ts' -o -name '*.js' \) | while IFS= read -r file; do
        rel="''${file#"$src_dir"/}"
        rel_no_ext="''${rel%.*}"
        ext="''${file##*.}"
        name="$(sanitize "$prefix-''${rel_no_ext}")"
        cp "$file" "$dest_dir/$name.$ext"
      done
    }

    copy_skill_dirs "${src.kdcoWorkspace}/src/skill" "kdco-workspace" "$out/skill"
    copy_skill_dirs "${src.kdcoWorkspace}/src/skills" "kdco-workspace" "$out/skill"
    copy_skill_dirs "${src.opencodeAgents}/.opencode/skill" "opencode-agents" "$out/skill"
    copy_skill_dirs "${src.opencodeAgents}/.opencode/skills" "opencode-agents" "$out/skill"

    copy_tool_flat "${src.redstone}/tools" "redstone" "$out/tool"
    copy_tool_flat "${src.opencodeAgents}/.opencode/tool" "opencode-agents" "$out/tool"

    cp "${src.kdcoBackgroundAgents}/src/plugin/background-agents.ts" "$out/plugins/kdco-background-agents.ts"
    cp "${src.morphFastApply}/index.ts" "$out/plugins/opencode-morph-fast-apply.ts"
    cp "${src.kdcoNotify}/src/notify.ts" "$out/plugins/kdco-notify.ts"
    cp "${src.kdcoWorktree}/src/plugin/worktree.ts" "$out/plugins/kdco-worktree.ts"
    cp "${src.kdcoWorkspace}/src/plugin/workspace-plugin.ts" "$out/plugins/kdco-workspace-plugin.ts"
    cp -R "${src.kdcoWorkspace}/src/plugin/kdco-primitives" "$out/plugins/kdco-primitives"
    cp -R "${src.kdcoWorktree}/src/plugin/worktree" "$out/plugins/worktree"

    cp "${src.opencodeAgents}/.opencode/plugin/notify.ts" "$out/plugins/opencode-agents-notify.ts"
    cp "${src.opencodeAgents}/.opencode/plugin/agent-validator.ts" "$out/plugins/opencode-agents-validator.ts"
    cp "${src.opencodeAgents}/.opencode/plugins/coder-verification/index.ts" "$out/plugins/opencode-agents-coder-verification.ts"

    cat > "$out/plugins/env-protection.ts" <<'EOF'
    import type { Plugin } from "@opencode-ai/plugin"

    export const EnvProtection: Plugin = async () => {
      return {
        tool: {
          execute: {
            before: async (input, output) => {
              if (input.tool === "read" && output.args.filePath.includes(".env")) {
                throw new Error("Do not read .env files")
              }
            },
          },
        },
      }
    }
    EOF

    cat > "$out/plugins/terminal-bell.ts" <<'EOF'
    import type { Plugin } from "@opencode-ai/plugin"

    export const TerminalBell: Plugin = async () => {
      return {
        event: async ({ event }) => {
          if (event.type === "session.idle") {
            await Bun.write(Bun.stdout, "\x07")
          }
        },
      }
    }
    EOF
  '';
in
{
  inherit agents commands themes;
  skillsDir = "${runtimeAssets}/skill";
  toolsDir = "${runtimeAssets}/tool";
  pluginsDir = "${runtimeAssets}/plugins";
  superpowersPlugin = builtins.toPath "${src.superpowers}/.opencode/plugins/superpowers.js";
  superpowersSkillsDir = builtins.toPath "${src.superpowers}/skills";
}
