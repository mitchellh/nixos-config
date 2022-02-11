## kubernetes

## Troubleshooting
- Install kubecolor
```sh
sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
sudo nix-channel --update
```
> if you want to test nixos-instable packages, try this
```sh
nix-shell -I nixpkgs=channel:nixos-unstable --packages kubecolor
```
