{ callPackage ? pkgs.callPackage
, pkgs ? import <nixpkgs> {} }:

callPackage (import ./hashicorp/generic.nix) {
  name = "terraform";
  version = "1.0.4";
  sha256 = "XAvk1S3nIUPizXjkF+4t1YLOIp1zeE/RlEREX6bhM14=";
}
