{ inputs, pkgs, ... }:

let
  awImportScreentimeSrc = pkgs.applyPatches {
    name = "aw-import-screentime-src";
    src = inputs.aw-import-screentime-src;
    patches = [ ../../patches/aw-import-screentime.patch ];
  };
  homeDir = "/Users/m";
  awAutomationScriptsRoot = "${homeDir}/.config/activitywatch/scripts";
  vmStaticIp = "192.168.130.3";
  openWebUiStateDir = "${homeDir}/.local/state/open-webui";
in
{
  imports = [ ./opencode/modules/darwin.nix ];

  homebrew = {
    enable = true;
    casks  = [
      "activitywatch"
      "karabiner-elements"
      "claude"
      "discord"
      "gimp"
      "google-chrome"
      "leader-key"
      "lm-studio"
      "loop"
      "launchcontrol"
      "mullvad-vpn"
      "orbstack"
      "spotify"
      "swiftbar"
    ];

    brews = [
      "gnupg"
      "kanata"
      "kanata-tray"
    ];

    masApps = {
      "Calflow"    = 6474122188;
      "Journal It"  = 6745241760;
      "Noir"        = 1592917505;
      "Perplexity"  = 6714467650;
      "Tailscale"   = 1475387142;
      "Telegram"    = 747648890;
      "Vimlike"     = 1584519802;
      "Wblock"      = 6746388723;
    };
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.m = {
    home = homeDir;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [ ../../machines/generated/mac-host-authorized-keys ];
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "m";

  system.defaults.CustomUserPreferences = {
    "com.apple.finder" = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      FXPreferredViewStyle = "Nlsv";
      CreateDesktop = false;
    };

    "com.apple.dock" = {
      autohide = true;
      tilesize = 36;
      magnification = true;
      largesize = 64;
      "minimize-to-application" = true;
      "show-recents" = false;
      "mru-spaces" = false;
      "expose-animation-duration" = 0.1;
      "autohide-delay" = 0.0;
      "autohide-time-modifier" = 0;
    };

    NSGlobalDomain = {
      KeyRepeat = 1;
      InitialKeyRepeat = 8;
      ApplePressAndHoldEnabled = false;
      "com.apple.mouse.scaling" = 0.0;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.trackpad.scaling" = 10.0;
      NSWindowShouldDragOnGesture = true;
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
    };

    "com.apple.screencapture" = {
      location = "/Users/m/Pictures/Screenshots";
      type = "png";
    };

    "com.apple.menuextra.clock" = {
      DateFormat = "EEE MMM d  H:mm";
    };

    "com.apple.speech.recognition.AppleSpeechRecognition.prefs" = {
      DictationIMAllowAudioDucking = false;
    };

    "com.apple.SpeechRecognitionCore" = {
      AllowAudioDucking = false;
    };
  };

  services.yabai.enable = true;
  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };


  # Uniclip: encrypted clipboard sharing between macOS and NixOS VM.
  # Server binds to VM network interface; VM connects directly (no SSH tunnel).
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
}
