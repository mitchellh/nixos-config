# den/aspects/features/darwin-desktop.nix
#
# Darwin desktop/window-management slice for macbook-pro-m1.
#
# Migrated from the legacy Darwin entrypoint during Task 11 of the den migration.
# Covers:
#   - macOS CustomUserPreferences
#   - yabai enablement
#   - skhd service + config
{ den, lib, ... }: {
  den.aspects.darwin-desktop = {
    includes = [
      ({ host, ... }:
        lib.optionalAttrs (host.class == "darwin") {
          darwin = { pkgs, ... }: {
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
              skhdConfig = builtins.readFile ../../../dotfiles/by-host/darwin/skhdrc;
            };
          };
        })
    ];
  };
}
