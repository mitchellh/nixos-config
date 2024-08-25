/* This contains various packages we want to overlay. Note that the
 * other ".nix" files in this directory are automatically loaded.
 */
final: prev: {
  consul-bin = final.callPackage ../pkgs/consul-bin.nix {};
  create-dmg = final.callPackage ../pkgs/create-dmg.nix {};
  nomad-bin = final.callPackage ../pkgs/nomad-bin.nix {};
  terraform-bin = final.callPackage ../pkgs/terraform-bin.nix {};

  # Fix 1password not working properly on Linux arm64.
  #_1password = final.callPackage ../pkgs/1password.nix {};
}
