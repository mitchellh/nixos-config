with import <nixpkgs> { };
let
  pname = "fix-vscode-remote";
  script = pkgs.writeShellScriptBin pname ''
    if [ -z "$1" ]; then
      echo "Please specify username."
      exit 1
    fi
    VSCODE_DIR="/home/$1/.vscode-server/bin"
    SCRIPT_DIR="$(dirname $0)"
    for versiondir in $VSCODE_DIR/*; do
      rm "$versiondir/node"
      ln -s "${nodePackage}/bin/node" "$versiondir/node"
    done
  '';
  nodePackage = nodejs-14_x;
in
{}:
stdenv.mkDerivation rec {
  name = pname;
  #nodePackage = nodejs-14_x; # This is vscode runtime
  src = ./.;
  installPhase = ''
    mkdir -p $out/bin
    cp ${script}/bin/${pname} $out/bin/${pname}
    cp ${nodePackage}/bin/node $out/bin/node
    chmod +x $out/bin/${pname}
  '';
  buildInputs = [ script nodePackage ];
}
