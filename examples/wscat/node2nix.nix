# nix-shell node2nix.nix --run "node2nix --development"
# [Isolated environments with nix-shell and zsh](https://msitko.pl/blog/2020/04/22/isolated-ennvironments-with-nix-shell-and-zsh.html)

# `--development` flag is crucial since we defined wscat as devDependency
# That generates `node-env.nix`, `node-packages.nix` and `default.nix`. 
# Having `default.nix` means that we can run `nix-shell -A shell --run fish`:

# It's because generated `default.nix` contains a few derivations. 
# We need to specify attribute path using `-A` option. 
# `node2nix` documentation mentions that you should use attribute `shell` , as in:

with import <nixpkgs> {};

stdenv.mkDerivation rec {
        name = "node2nix";
        buildInputs = [ nodePackages.node2nix ];
}
