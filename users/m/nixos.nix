{ pkgs, inputs, config, lib, isWSL, ... }:

let
  hostAuthorizedKeysFile = ../../machines/generated/host-authorized-keys;
in

{
  # Write rbw config from sops-decrypted email (keeps email out of public repo)
  systemd.user.services.rbw-config = {
    description = "Write rbw config from sops secrets";
    after = [ "default.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let
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
            --arg pinentry "${(if isWSL then pkgs.pinentry-tty else pkgs.wayprompt)}/bin/${if isWSL then "pinentry-tty" else "pinentry-wayprompt"}" \
            '{base_url: $base_url, email: $email, lock_timeout: $lock_timeout, pinentry: $pinentry}' \
            > "$HOME/.config/rbw/config.json"
        '';
      in "${script}";
    };
  };

  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/zsh" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using zsh as our shell
  programs.zsh.enable = true;

  # We require this because we use lazy.nvim against the best wishes
  # a pure Nix system so this lets those unpatched binaries run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  users.users.m = {
    isNormalUser = true;
    home = "/home/m";
    extraGroups = [ "lxd" "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets."user/hashed-password".path;
    openssh.authorizedKeys.keyFiles = [ hostAuthorizedKeysFile ];
  };
}
