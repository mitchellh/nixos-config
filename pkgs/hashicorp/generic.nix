/* This function creates a derivation for installing binaries directly
 * from releases.hashicorp.com.
 */
{ name
, version
, sha256
, system ? builtins.currentSystem
, pname ? "${name}-bin"

, lib
, stdenv
, fetchurl
, unzip
, autoPatchelfHook
}:

let
  # Mapping of Nix systems to the GOOS/GOARCH pairs.
  systemMap = {
    x86_64-linux  = "linux_amd64";
    i686-linux    = "linux_386";
    x86_64-darwin = "darwin_amd64";
    i686-darwin   = "darwin_386";
    aarch64-linux = "linux_arm64";
  };

  # Get our system
  goSystem = systemMap.${system} or (throw "unsupported system: ${system}");

  # url for downloading composed of all the other stuff we built up.
  url = "https://releases.hashicorp.com/${name}/${version}/${name}_${version}_${goSystem}.zip";
in stdenv.mkDerivation {
  inherit pname version;
  src = fetchurl { inherit url sha256; };

  # Our source is right where the unzip happens, not in a "src/" directory (default)
  sourceRoot = ".";

  # Stripping breaks darwin Go binaries
  dontStrip = lib.strings.hasPrefix "darwin" goSystem;

  nativeBuildInputs = [ unzip ] ++ (if stdenv.isLinux then [
    # On Linux we need to do this so executables work
    autoPatchelfHook
  ] else []);

  installPhase = ''
    mkdir -p $out/bin
    mv ${name} $out/bin
  '';
}
