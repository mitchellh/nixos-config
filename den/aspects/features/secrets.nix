# den/aspects/features/secrets.nix
#
# Secret-backed and sops system configuration aspect for user m.
#
# Migrated from the legacy VM shared and Linux user entrypoints (Task 7 of den migration).
# Covers: default secrets file, age/gnupg config, sops secrets, Tailscale auth
#         from secret, mutableUsers=false, hashedPasswordFile, and the rbw-config
#         systemd user service.
#
# Host-aware guards use den host context (host.wsl.enable or false) rather than
# the legacy top-level isWSL arg for pinentry selection. Even though this aspect
# is only attached to vm-aarch64 in Task 7, the host-aware pattern keeps the
# logic den-native and reusable later.
{ den, lib, generated, inputs, ... }: {

  den.aspects.secrets = {
    includes = [
      ({ host, ... }:
        let
          isWSL = host.wsl.enable or false;
        in {
          nixos = { config, pkgs, lib, ... }: {
            imports = [
              inputs.sops-nix.nixosModules.sops
              inputs.sopsidy.nixosModules.default
            ];

            # sops-nix: default secrets file
            # ---------------------------------------------------------------

            sops.defaultSopsFile = generated.requireFile "secrets.yaml";

            # ---------------------------------------------------------------
            # sops-nix: age + gnupg key paths
            # ---------------------------------------------------------------

            sops.age.keyFile = "/var/lib/sops-nix/key.txt";
            sops.age.generateKey = true;
            sops.age.sshKeyPaths = [];
            sops.gnupg.sshKeyPaths = [];

            # ---------------------------------------------------------------
            # sops secrets
            # ---------------------------------------------------------------

            sops.secrets."tailscale/auth-key" = {
              collect.rbw.id = "tailscale-auth-key";
            };
            sops.secrets."rbw/email" = {
              collect.rbw.id = "bitwarden-email";
              owner = "m";
              mode = "0400";
            };
            sops.secrets."uniclip/password" = {
              collect.rbw.id = "uniclip-password";
              owner = "m";
              mode = "0400";
            };
            sops.secrets."user/hashed-password" = {
              collect.rbw.id = "nixos-hashed-password";
              neededForUsers = true;
            };

            # ---------------------------------------------------------------
            # Tailscale: authenticate from secret
            # ---------------------------------------------------------------

            services.tailscale.enable = true;
            services.tailscale.authKeyFile =
              config.sops.secrets."tailscale/auth-key".path;

            # ---------------------------------------------------------------
            # Users: disable mutable users (passwords come from sops)
            # ---------------------------------------------------------------

            users.mutableUsers = false;

            # ---------------------------------------------------------------
            # User m: hashed password from sops secret
            # ---------------------------------------------------------------

            users.users.m.hashedPasswordFile =
              config.sops.secrets."user/hashed-password".path;

            # ---------------------------------------------------------------
            # rbw-config: write rbw config from sops-decrypted email
            #
            # Uses host.wsl.enable (closed over above) to pick the right
            # pinentry binary rather than the legacy top-level isWSL arg.
            # ---------------------------------------------------------------

            systemd.user.services.rbw-config = {
              description = "Write rbw config from sops secrets";
              after = [ "default.target" ];
              wantedBy = [ "default.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart =
                  let
                    pinentryPkg = if isWSL then pkgs.pinentry-tty else pkgs.wayprompt;
                    pinentryBin = if isWSL then "pinentry-tty" else "pinentry-wayprompt";
                    script = pkgs.writeShellScript "write-rbw-config" ''
                      set -euo pipefail
                      email_file="/run/secrets/rbw/email"
                      if [ ! -f "$email_file" ]; then
                        echo "rbw-config: $email_file not found, skipping" >&2
                        exit 0
                      fi
                      mkdir -p "$HOME/.config/rbw"
                      ${pkgs.jq}/bin/jq -n \
                        --arg base_url "https://api.bitwarden.eu" \
                        --arg email "$(cat "$email_file")" \
                        --argjson lock_timeout 86400 \
                        --arg pinentry "${pinentryPkg}/bin/${pinentryBin}" \
                        '{base_url: $base_url, email: $email, lock_timeout: $lock_timeout, pinentry: $pinentry}' \
                        > "$HOME/.config/rbw/config.json"
                    '';
                  in "${script}";
              };
            };
          };
        })
    ];
  };

}
