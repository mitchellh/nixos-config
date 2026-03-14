# den/aspects/features/homebrew.nix
#
# Homebrew slice for macbook-pro-m1.
#
# Migrated from the legacy Darwin entrypoint (Task 9 of den migration).
{ den, ... }: {
  den.aspects.homebrew = {
    includes = [
      ({ ... }: {
        darwin = { ... }: {
          homebrew.enable = true;
          homebrew.taps = [
            "lujstn/tap"
          ];
          homebrew.casks = [
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
          homebrew.brews = [
            "gnupg"
            "kanata"
            "kanata-tray"
            "pinentry-touchid"
          ];
          homebrew.masApps = {
            "Calflow" = 6474122188;
            "Journal It" = 6745241760;
            "Noir" = 1592917505;
            "Perplexity" = 6714467650;
            "Tailscale" = 1475387142;
            "Telegram" = 747648890;
            "Vimlike" = 1584519802;
            "Wblock" = 6746388723;
          };
        };
      })
    ];
  };
}
