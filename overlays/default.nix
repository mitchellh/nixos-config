/* This contains various packages we want to overlay. Note that the
 * other ".nix" files in this directory are automatically loaded.
 */
self: super: {
  consul-bin = self.callPackage ../pkgs/consul-bin.nix {};
  create-dmg = self.callPackage ../pkgs/create-dmg.nix {};
  nomad-bin = self.callPackage ../pkgs/nomad-bin.nix {};
  terraform-bin = self.callPackage ../pkgs/terraform-bin.nix {};

  # Have to force Go 1.17 because the default is fixed to 1.16
  # for reasons in the nixpkgs repository. We'll undo this when
  # they switch.
  go = self.go_1_17;
}
