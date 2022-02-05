# nix-shell --pure --show-trace kube-shell.nix

with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "kube-env";

  buildInputs = [
    pkgs.kubectl
    pkgs.minikube
    pkgs.kustomize
    pkgs.kubernetes-helm
    
    # cluster management tool
    pkgs.k9s
    pkgs.lens
    pkgs.krew
    # pkgs.kubecolor #TODO unstable
    
    pkgs.kind  
  ];

  # The '' quotes are 2 single quote characters
  # They are used for multi-line strings
  shellHook = ''
    figlet "Welcome!" | lolcat --freq 0.5
  '';
}
