let sources = import ../nix/sources.nix; in
self: super: {
  /*
  I use a shell.nix in most places so let's just use what Nix provides.

  go = super.go.overrideAttrs (oldAttrs: rec {
    version = super.lib.strings.removePrefix "go" sources.go.branch;
    src = sources.go;
  });
  */
}
