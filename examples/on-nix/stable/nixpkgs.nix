# /path/to/my/expression.nix

let
  # Import Nixpkgs
  nixpkgs = import <nixpkgs> { };

  # Import Python on Nix
  pythonOnNix = import
    # (builtins.fetchGit {
    #   # Use `main` branch or a commit from this list:
    #   # https://github.com/on-nix/python/commits/main
    #   # We recommend using a commit for maximum reproducibility
    #   ref = "main";
    #   url = "https://github.com/on-nix/python";
    # })
    (../../.)
    {
      # (optional) You can override `nixpkgs` here
      inherit nixpkgs;
    };

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
  # - `out`: The raw contents of the Python virtual environment
in
# Let's use the activation script:
nixpkgs.stdenv.mkDerivation {
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
  name = "example";
}
