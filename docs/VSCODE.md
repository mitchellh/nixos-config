
Troubleshooting vscode-ssh-remote extension missing node
https://github.com/cprussin/nixjs

nodejs.nix
```shell
{
  nodejs ? "12.16.2",
  yarn ? "1.22.4",
  nixjs ? fetchTarball "https://github.com/cprussin/nixjs/tarball/release-20.03",
  nixpkgs ? <nixpkgs>
}:

let
  nixjs-overlay = import nixjs {
    inherit nixpkgs;
    versions = {
      inherit nodejs yarn;
    };
  };
  pkgs = import nixpkgs { overlays = [ nixjs-overlay ]; };
in

pkgs.mkShell {
  buildInputs = [ pkgs.nodejs pkgs.yarn ];
}
```

nix-shell nodejs.nix


Remote-ssh mac to nixos

cd /home/zerodeth/.vscode-server/bin/899d46d82c4c95423fb7e10e68eba52050e30ba3/
rm -rf node; sudo ln -s "$(which node)" node
