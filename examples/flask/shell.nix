with import <nixpkgs> {};

stdenv.mkDerivation rec {
  name = "python-environment";

  buildInputs = [ pkgs.python38 pkgs.python38Packages.flask pkgs.ffmpeg ];

  shellHook = ''
    export FLASK_DEBUG=1
    export FLASK_APP="main.py"

    export API_KEY="some secret key"
  '';
}
