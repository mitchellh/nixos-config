with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "keybase-env";

  buildInputs = [
    pkgs.keybase
    pkgs.keybase-gui
    pkgs.kbfs
  ];

  # The '' quotes are 2 single quote characters
  # They are used for multi-line strings
  shellHook = ''
    keybase login zerodeth
  '';
}
