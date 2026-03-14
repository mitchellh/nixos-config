{ isWSL }:
{ lib, pkgs, ... }:

let
  opencode = import ./common.nix;
  isLinux = pkgs.stdenv.isLinux;
in {
  programs.zsh.shellAliases = {
    opencode-dev = "${pkgs.opencode-dev}/bin/opencode";
  };

  programs.bash.shellAliases = {
    opencode-dev = "${pkgs.opencode-dev}/bin/opencode";
  };

  systemd.user.services.opencode-serve = lib.mkIf (isLinux && !isWSL) {
    Unit = {
      Description = "OpenCode stable server (serve mode)";
      After = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.llm-agents.opencode}/bin/opencode models --refresh";
      ExecStart = "${pkgs.llm-agents.opencode}/bin/opencode serve --mdns --mdns-domain ${opencode.stableMdnsDomain} --port ${toString opencode.stablePort}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.opencode-web = lib.mkIf (isLinux && !isWSL) {
    Unit = {
      Description = "OpenCode web interface (patched dev)";
      After = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.opencode-dev}/bin/opencode models --refresh";
      ExecStart = "${pkgs.opencode-dev}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port ${toString opencode.webPort}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
