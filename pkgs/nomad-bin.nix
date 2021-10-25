{ callPackage ? pkgs.callPackage
, pkgs ? import <nixpkgs> {} }:

callPackage (import ./hashicorp/generic.nix) {
  name = "nomad";
  version = "1.0.4";
  sha256 = "0h78akj9hczgv4wrzwy93wxh8ki51b0g55n39i8ak3kc6sqvif6v";
}
