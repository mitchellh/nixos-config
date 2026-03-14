let
  stablePort = 53721;
  devPort = 53722;
  webPort = 53723;
in {
  inherit stablePort devPort webPort;
  stableUrl = "http://127.0.0.1:${toString stablePort}";
  devUrl = "http://127.0.0.1:${toString devPort}";
  stableMdnsDomain = "opencode-stable.local";
  devMdnsDomain = "opencode-dev.local";
  webMdnsDomain = "opencode-web.local";
}
