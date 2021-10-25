let sources = import ../nix/sources.nix; in
self: super: {
  buildpack = super.buildpack.overrideAttrs (oldAttrs: rec {
    version = super.lib.strings.removePrefix "v" sources.pack.branch;
    src = sources.pack;
    buildFlagsArray = [ "-ldflags=-s -w -X github.com/buildpacks/pack/cmd.Version=${version}" ];
  });
}
