# den/aspects/features/launchd.nix
#
# Darwin launchd slice for macbook-pro-m1.
#
# Migrated from the legacy Darwin entrypoint (Task 9 of den migration).
# Covers the custom launchd user agents for host/guest services, local
# automation, and the opencode darwin launchd module.
{ den, inputs, ... }: {
  den.aspects.launchd = {
    includes = [
      ({ ... }: {
        darwin = { pkgs, ... }:
          let
            awImportScreentimeSrc = pkgs.applyPatches {
              name = "aw-import-screentime-src";
              src = inputs.aw-import-screentime-src;
              patches = [ ../../../patches/aw-import-screentime.patch ];
            };
            homeDir = "/Users/m";
            awAutomationScriptsRoot = "${homeDir}/.config/activitywatch/scripts";
            vmStaticIp = "192.168.130.3";
            openWebUiStateDir = "${homeDir}/.local/state/open-webui";
          in {
            imports = [ ../../../dotfiles/common/opencode/modules/darwin.nix ];

            # Uniclip: encrypted clipboard sharing between macOS and NixOS VM.
            # Server binds to 192.168.130.1 (macOS host-side VMware interface); VM connects directly (no SSH tunnel).
            launchd.user.agents.uniclip = {
              serviceConfig = {
                ProgramArguments = [
                  "/bin/bash" "-c"
                  ''
                    set -euo pipefail
                    /bin/wait4path /nix/store
                    export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
                    UNICLIP_PASSWORD="$(${pkgs.rbw}/bin/rbw get uniclip-password)"
                    if [ -z "$UNICLIP_PASSWORD" ]; then
                      echo "uniclip: empty password from rbw" >&2
                      exit 1
                    fi
                    export UNICLIP_PASSWORD
                    exec ${pkgs.uniclip}/bin/uniclip --secure --bind 192.168.130.1 -p 53701
                  ''
                ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/tmp/uniclip-server.log";
                StandardErrorPath = "/tmp/uniclip-server.log";
              };
            };

            launchd.user.agents.openwebui = {
              serviceConfig = {
                ProgramArguments = [
                  "/bin/bash" "-c"
                  ''
                    /bin/wait4path /nix/store
                    mkdir -p "${openWebUiStateDir}"/{static,data,hf_home,transformers_home}
                    export PATH=${pkgs.uv}/bin:$PATH
                    export STATIC_DIR="${openWebUiStateDir}/static"
                    export DATA_DIR="${openWebUiStateDir}/data"
                    export HF_HOME="${openWebUiStateDir}/hf_home"
                    export SENTENCE_TRANSFORMERS_HOME="${openWebUiStateDir}/transformers_home"
                    export WEBUI_URL="http://localhost:8080"
                    export SCARF_NO_ANALYTICS=True
                    export DO_NOT_TRACK=True
                    export ANONYMIZED_TELEMETRY=False
                    cd "${openWebUiStateDir}"
                    exec ${pkgs.uv}/bin/uvx --python 3.11 open-webui@latest serve --host 127.0.0.1 --port 8080
                  ''
                ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/tmp/openwebui.log";
                StandardErrorPath = "/tmp/openwebui.log";
              };
            };

            # Expose Open WebUI inside the VM on localhost:80.
            launchd.user.agents.openwebui-tunnel = {
              serviceConfig = {
                ProgramArguments = [
                  "/bin/bash" "-c"
                  ''
                    while true; do
                      /usr/bin/ssh-keygen -R "${vmStaticIp}" >/dev/null 2>&1 || true
                      /usr/bin/ssh -N \
                        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                        -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                        -R 18080:127.0.0.1:8080 m@${vmStaticIp}
                      sleep 5
                    done
                  ''
                ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/tmp/openwebui-tunnel.log";
                StandardErrorPath = "/tmp/openwebui-tunnel.log";
              };
            };

            # Expose ActivityWatch server inside the VM on localhost:5600.
            launchd.user.agents.activitywatch-tunnel = {
              serviceConfig = {
                ProgramArguments = [
                  "/bin/bash" "-c"
                  ''
                    while true; do
                      /usr/bin/ssh-keygen -R "${vmStaticIp}" >/dev/null 2>&1 || true
                      /usr/bin/ssh -N \
                        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                        -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                        -R 5600:127.0.0.1:5600 m@${vmStaticIp}
                      sleep 5
                    done
                  ''
                ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/tmp/activitywatch-tunnel.log";
                StandardErrorPath = "/tmp/activitywatch-tunnel.log";
              };
            };

            launchd.user.agents.kanata-tray = {
              serviceConfig = {
                ProgramArguments = [ "sudo" "/opt/homebrew/bin/kanata-tray" ];
                EnvironmentVariables = {
                  KANATA_TRAY_CONFIG_DIR = "/Users/m/.config/kanata-tray";
                  KANATA_TRAY_LOG_DIR = "/tmp";
                };
                StandardOutPath = "/tmp/kanata-try.out.log";
                StandardErrorPath = "/tmp/kanata-tray.err.log";
                RunAtLoad = true;
                KeepAlive = true;
                LimitLoadToSessionType = "Aqua";
                ProcessType = "Interactive";
                ThrottleInterval = 20;
              };
            };

            launchd.user.agents.activitywatch-sync-aw-to-calendar = {
              serviceConfig = {
                ProgramArguments = [
                  "/usr/bin/osascript"
                  "-l"
                  "JavaScript"
                  "${awAutomationScriptsRoot}/synchronize.js"
                ];
                RunAtLoad = true;
                StartInterval = 1800;
                WorkingDirectory = awAutomationScriptsRoot;
                StandardOutPath = "/tmp/aw-sync-aw-to-calendar.out.log";
                StandardErrorPath = "/tmp/aw-sync-aw-to-calendar.err.log";
              };
            };

            launchd.user.agents.activitywatch-sync-ios-screentime-to-aw = {
              serviceConfig = {
                ProgramArguments = [
                  "/Applications/LaunchControl.app/Contents/MacOS/fdautil"
                  "exec"
                  "/bin/bash"
                  "${awAutomationScriptsRoot}/run_sync.sh"
                ];
                EnvironmentVariables = {
                  AW_IMPORT_SRC = "${awImportScreentimeSrc}";
                  PATH = "/etc/profiles/per-user/m/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin";
                };
                RunAtLoad = true;
                StartInterval = 3600;
                WorkingDirectory = awAutomationScriptsRoot;
                StandardOutPath = "/tmp/aw-sync-ios-screentime-to-aw.out.log";
                StandardErrorPath = "/tmp/aw-sync-ios-screentime-to-aw.err.log";
              };
            };

            launchd.user.agents.activitywatch-bucketize-aw-and-sync-to-calendar = {
              serviceConfig = {
                ProgramArguments = [
                  "/usr/bin/osascript"
                  "-l"
                  "JavaScript"
                  "${awAutomationScriptsRoot}/bucketize.js"
                ];
                RunAtLoad = true;
                StartInterval = 900;
                WorkingDirectory = awAutomationScriptsRoot;
                StandardOutPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.out.log";
                StandardErrorPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.err.log";
              };
            };
          };
      })
    ];
  };
}
