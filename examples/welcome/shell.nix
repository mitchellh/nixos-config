with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "greetings-env";

  buildInputs = [
    pkgs.figlet
    pkgs.lolcat
  ];

  # The '' quotes are 2 single quote characters
  # They are used for multi-line strings
  shellHook = ''
    figlet "Welcome!" | lolcat --freq 0.5
  '';
}
