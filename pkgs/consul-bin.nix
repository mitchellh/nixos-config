{ callPackage ? pkgs.callPackage
, pkgs ? import <nixpkgs> {} }:

callPackage (import ./hashicorp/generic.nix) {
  name = "consul";
  version = "1.7.3";
  sha256 = "1hws7zfj2g1ag20hqv1yvcrn95q1l7r8ay9vhkwc2aqcbnm18f25";
}
