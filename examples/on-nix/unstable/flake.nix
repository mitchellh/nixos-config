{
  inputs = {
    flakeUtils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs";
    # Import Python on Nix
    # pythonOnNix.url = "github:on-nix/python";
    pythonOnNix.url = "/data/github/on-nix/python";
    pythonOnNix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, ... } @ inputs:
    inputs.flakeUtils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        nixpkgs = inputs.nixpkgs.legacyPackages.${system};
        pythonOnNix = inputs.pythonOnNix.lib.${system};

        # Pick the Python version of your choice:
        # - `python37Env`: Python 3.7
        # - `python38Env`: Python 3.8
        # - `python39Env`: Python 3.9
        # - `python310Env`: Python 3.10
        env = pythonOnNix.python39Env {
          name = "example";
          projects = {
            awscli = "1.20.31";
            numpy = "latest";
            requests = "latest";
            torch = "1.9.0";
          };
        };
        # `env` has two attributes:
        # - `dev`: The activation script for the Python on Nix environment
        # - `out`: The raw contents fo the Python site-packages
      in
      {
        devShells = {

          # The activation script can be used as dev-shell
          example = env.dev;

        };
        packages = rec {

          something = nixpkgs.stdenv.mkDerivation {
            buildInputs = [ env.dev ];
            virtualEnvironment = env.out;

            builder = builtins.toFile "builder.sh" ''
              source $stdenv/setup

              set -x

              ls $virtualEnvironment
              python --version
              aws --version
              python -c 'import numpy; print(numpy.__version__)'
              python -c 'import requests; print(requests.__version__)'
              python -c 'import torch; print(torch.__version__)'

              touch $out

              set +x
            '';
            name = "something";
          };

        };
      }
    );
}
