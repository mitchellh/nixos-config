# fnix nixos-config/examples/kube/kube-shell.nix

with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "kube-env";

  buildInputs = [
    pkgs.figlet
    pkgs.lolcat

    pkgs.kubectl
    pkgs.minikube
    pkgs.kustomize
    pkgs.kubernetes-helm

    # cluster management tool
    pkgs.k9s
    pkgs.lens
    pkgs.krew
    pkgs.kubecolor       //TODO: nixos-unstable has this, update channel to use it.
    pkgs.kind                    # kubernetes in docker
  ];

  # The '' quotes are 2 single quote characters
  # They are used for multi-line strings
  shellHook = ''
    figlet "Kube World!" | lolcat --freq 0.5

    kubectl version              #v1.22.6
    minikube version             #v1.25.1
    kustomize version            #v4.4.1
    helm version                 #v0.9.0
    k9s version                  #v0.25.18
    krew version                 #v0.4.2
    kind version                 #v0.11.1
  '';
}
