# den/aspects/features/gpg.nix
#
# GPG agent, git signing, and login passphrase preset aspect for user m.
#
# Migrated from the legacy Home Manager entrypoint (Task 5 of den migration).
# Covers: programs.gpg, services.gpg-agent, programs.git.signing,
#         gpgPresetPassphraseLogin helper script (vm-aarch64 only), and the
#         systemd login service that presets the signing passphrase (vm only).
#
# Host-aware guards use den host context rather than the legacy system-name string:
#   isDarwin  — host.class == "darwin"
#   isLinux   — host.class == "nixos"
#   isVM      — host.vmware.enable or false  (only vm-aarch64 sets this)
{ den, lib, ... }: {

  den.aspects.gpg = {
    includes = [
      ({ host, ... }:
        let
          isDarwin = host.class == "darwin";
          isLinux  = host.class == "nixos";
          isVM     = host.vmware.enable or false;

          legacyGitSigningKey = "247AE5FC6A838272";
          macosGitSigningKey = "9317B542250D33B34C41F62831D3B9C9754C0F5B";
          vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";

          gitSigningKey =
            if isDarwin then macosGitSigningKey
            else if isVM then vmGitSigningKey
            else legacyGitSigningKey;

          darwinPinentryProgram = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid";
        in {
          homeManager = { pkgs, lib, ... }:
            let
              gpgPresetPassphraseLogin = pkgs.writeShellScriptBin "gpg-preset-passphrase-login" ''
                set -euo pipefail

                if ! passphrase="$(${pkgs.rbw}/bin/rbw get gpg-password-nixos-macbook-vm)"; then
                  echo "gpg-preset-passphrase-login: failed to read gpg-password-nixos-macbook-vm from rbw" >&2
                  exit 1
                fi

                if [ -z "$passphrase" ]; then
                  echo "gpg-preset-passphrase-login: empty passphrase from rbw" >&2
                  exit 1
                fi

                mapfile -t keygrips < <(
                  ${pkgs.gnupg}/bin/gpg --batch --with-colons --with-keygrip --list-secret-keys ${vmGitSigningKey} \
                    | ${pkgs.gawk}/bin/awk -F: '$1 == "grp" && $10 != "" { print $10 }'
                )
                if [ "''${#keygrips[@]}" -eq 0 ]; then
                  echo "gpg-preset-passphrase-login: failed to resolve keygrip for ${vmGitSigningKey}" >&2
                  exit 1
                fi

                ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null
                for keygrip in "''${keygrips[@]}"; do
                  printf '%s' "$passphrase" | ${pkgs.gnupg}/bin/gpg-preset-passphrase --preset "$keygrip"
                done
              '';
            in {
              # ---------------------------------------------------------------
              # GPG
              # ---------------------------------------------------------------
              programs.gpg.enable = true;

              # VM only: install the login passphrase helper
              home.packages = lib.optionals isVM [
                gpgPresetPassphraseLogin
              ];

              # ---------------------------------------------------------------
              # GPG agent
              # ---------------------------------------------------------------
              services.gpg-agent = {
                enable = isLinux || isDarwin;
                pinentry.package = lib.mkIf isLinux pkgs.pinentry-tty;
                extraConfig = lib.concatStringsSep "\n" (lib.filter (line: line != "") [
                  (lib.optionalString isDarwin "pinentry-program ${darwinPinentryProgram}")
                  (lib.optionalString isVM "allow-preset-passphrase")
                ]);

                # Keep Darwin's internal agent cache effectively off so Touch ID can gate
                # each signing operation without pinentry-touchid being bypassed.
                defaultCacheTtl = if isDarwin then 1 else 31536000;
                maxCacheTtl = if isDarwin then 1 else 31536000;
              };

              # ---------------------------------------------------------------
              # Git signing
              # ---------------------------------------------------------------
              programs.git = {
                signing = {
                  key = gitSigningKey;
                  signByDefault = true;
                };
                settings.gpg.program = if isDarwin then "/opt/homebrew/bin/gpg" else "${pkgs.gnupg}/bin/gpg";
              };

              # ---------------------------------------------------------------
              # Systemd login service — preset GPG passphrase at login (vm only)
              # ---------------------------------------------------------------
              systemd.user.services.gpg-preset-passphrase-login = lib.mkIf isVM {
                Unit = {
                  Description = "Preset GPG signing passphrase on login";
                  After = [ "default.target" "rbw-config.service" ];
                  Wants = [ "rbw-config.service" ];
                };
                Service = {
                  Type = "oneshot";
                  ExecStart = "${gpgPresetPassphraseLogin}/bin/gpg-preset-passphrase-login";
                  Restart = "on-failure";
                  RestartSec = 30;
                };
                Install.WantedBy = [ "default.target" ];
              };
            };
        })
    ];
  };

}
