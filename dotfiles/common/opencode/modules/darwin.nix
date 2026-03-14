{ pkgs, ... }:

let
  opencode = import ./common.nix;
in {
  launchd.user.agents.opencode-serve = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          ${pkgs.llm-agents.opencode}/bin/opencode models --refresh
          exec ${pkgs.llm-agents.opencode}/bin/opencode serve --mdns --mdns-domain ${opencode.stableMdnsDomain} --port ${toString opencode.stablePort}
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/opencode-serve.log";
      StandardErrorPath = "/tmp/opencode-serve.log";
    };
  };

  launchd.user.agents.opencode-web = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          ${pkgs.opencode-dev}/bin/opencode models --refresh
          exec ${pkgs.opencode-dev}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port ${toString opencode.webPort}
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/opencode-web.log";
      StandardErrorPath = "/tmp/opencode-web.log";
    };
  };
}
