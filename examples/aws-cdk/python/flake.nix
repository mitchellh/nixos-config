# Save this file as: ./flake.nix

{
  inputs = {
    flakeUtils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs";
    pythonOnNix.url = "github:on-nix/python/2e735762c73651cffc027ca850b2a58d87d54b49";
    pythonOnNix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, ... } @ inputs:
    inputs.flakeUtils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        nixpkgs = inputs.nixpkgs.legacyPackages.${system};
        pythonOnNix = inputs.pythonOnNix.lib.${system};

        env = pythonOnNix.python39Env {
          name = "aws-cdk";
          projects = {
            "aws-cdk-aws-ec2" = "latest";
            # You can add more projects here as you need
            "awscli" = "latest";
            # "b" = "2.0";
            # ...
          };
        };
        # `env` has two attributes:
        # - dev: The activation script for the Python on Nix environment
        # - out: The raw contents of the Python site-packages
      in
      {
        devShells = {

          # The activation script can be used as dev-shell
          shell = env.dev;

        };

        packages = {

          # You can also use with Nixpkgs
          env = nixpkgs.stdenv.mkDerivation {
            # Let's use the activation script as build input
            # so the Python environment is loaded
            buildInputs = [ env.dev ];
            virtualEnvironment = env.out;

            builder = builtins.toFile "builder.sh" ''
              source $stdenv/setup

              # aws-cdk-aws-ec2 will be available here!

              touch $out
            '';
            name = "aws-cdk";
          };

        };
      }
    );
}

# Usage:
#   First add your changes:
#     $ git add flake.nix
#
#   Dev Shell:
#     $ nix develop .#shell
#
#   Build example:
#     $ nix build .#aws-cdk
