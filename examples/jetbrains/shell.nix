# Incompatibility with Nix Package manager
# https://youtrack.jetbrains.com/issue/CWM-5048

# export NIXPKGS_ALLOW_UNFREE=1

# starts a shell with Goland (`jetbrains.goland`) and latest Golang (`go`) installed
nix-shell -p jetbrains.goland go zsh

# Optional: change to your preferred shell
zsh

# Inside the shell, start the remote-dev-server
"$(dirname $(which goland))"/../goland-2021.3.2/bin/remote-dev-server.sh run .
