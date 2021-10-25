/* This contains various packages we want to overlay. Note that the
 * other ".nix" files in this directory are automatically loaded.
 */
self: super: {
  consul-bin = self.callPackage ../pkgs/consul-bin.nix {};
  create-dmg = self.callPackage ../pkgs/create-dmg.nix {};
  nomad-bin = self.callPackage ../pkgs/nomad-bin.nix {};
  terraform-bin = self.callPackage ../pkgs/terraform-bin.nix {};
}
