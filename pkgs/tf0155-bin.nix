/* nix profile install -f pkgs/tf0155-bin.nix */
{ callPackage ? pkgs.callPackage
, pkgs ? import <nixpkgs> {} }:

callPackage (import ./hashicorp/generic.nix) {
  name = "terraform";
  version = "0.15.5";
  sha256 = "sha256-OxREmeCMJFqAOQJ+srhMBJXhGfV9eej7YFhku0iJen0=";
}
