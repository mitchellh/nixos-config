# AWS CDK v1/2 

[on-nix/python](https://github.com/on-nix/python) Try it out:

## Nix stable:
```sh
$ nix-shell \
  --attr 'projects."aws-cdk-aws-ec2"."latest".python37.dev' \
  'https://github.com/on-nix/python/tarball/2e735762c73651cffc027ca850b2a58d87d54b49'
```
## Nix Flakes:
```sh
$ nix develop \
  'github:on-nix/python/2e735762c73651cffc027ca850b2a58d87d54b49#"aws-cdk-aws-ec2-latest-python37"'
Install aws-cdk-aws-ec2's command line applications in your system:
```
## Nix stable:
```sh
$ nix-env --install \
  --attr 'apps."aws-cdk-aws-ec2"."latest"' \
  --file 'https://github.com/on-nix/python/tarball/2e735762c73651cffc027ca850b2a58d87d54b49'
```
## Nix Flakes:
```sh
$ nix profile install \
  'github:on-nix/python#"aws-cdk-aws-ec2-latest-python37-bin"'
```

## Use many Python projects together:
### Nix stable:
```sh
# Save this file as: ./example.nix

let
  # Import Nixpkgs
  nixpkgs = import <nixpkgs> { };

  # Import Python on Nix
  pythonOnNix = import
    (builtins.fetchGit {
      ref = "main";
      rev = "2e735762c73651cffc027ca850b2a58d87d54b49";
      url = "https://github.com/on-nix/python";
    })
    { inherit nixpkgs; };

  env = pythonOnNix.python37Env {
    name = "example";
    projects = {
      "aws-cdk-aws-ec2" = "latest";
      # You can add more projects here as you need
      # "a" = "1.0";
      # "b" = "2.0";
      # ...
    };
  };

  # `env` has two attributes:
  # - dev: The activation script for the Python on Nix environment
  # - out: The raw contents of the Python site-packages
in
{
  # The activation script can be used as dev-shell
  shell = env.dev;

  # You can also use with Nixpkgs
  example = nixpkgs.stdenv.mkDerivation {
    # Let's use the activation script as build input
    # so the Python environment is loaded
    buildInputs = [ env.dev ];

    builder = builtins.toFile "builder.sh" ''
      source $stdenv/setup

      # aws-cdk-aws-ec2 will be available here!

      touch $out
    '';
    name = "example";
  };
}

# Usage:
#
#   Dev Shell:
#     $ nix-shell --attr shell ./example.nix
#
#   Build example:
#     $ nix-build --attr example ./example.nix
```

### Nix Flakes:
```sh
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

        env = pythonOnNix.python37Env {
          name = "example";
          projects = {
            "aws-cdk-aws-ec2" = "latest";
            # You can add more projects here as you need
            # "a" = "1.0";
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
          example = nixpkgs.stdenv.mkDerivation {
            # Let's use the activation script as build input
            # so the Python environment is loaded
            buildInputs = [ env.dev ];
            virtualEnvironment = env.out;

            builder = builtins.toFile "builder.sh" ''
              source $stdenv/setup

              # aws-cdk-aws-ec2 will be available here!

              touch $out
            '';
            name = "example";
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
#     $ nix build .#example
```
