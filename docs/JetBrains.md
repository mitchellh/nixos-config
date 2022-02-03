# JetBrains

## GoLand

### Troubleshooting
- `/home/zerodeth/.cache/JetBrains/RemoteDev-GO/_home_zerodeth_code_nixos-config/pid.688044.temp.jbr/bin/java: line 2: /lib64/ld-linux-x86-64.so.2: No such file or directory`
[Request: JetBrains remote-dev-server #153335](https://github.com/NixOS/nixpkgs/issues/153335#issuecomment-1015590704)
[Incompatibility with Nix Package manager](https://youtrack.jetbrains.com/issue/CWM-5048)
```sh
# creates a shell with goland binary in PATH
nix-shell -p jetbrains.goland
# starts goland
goland
```
```sh
export NIXPKGS_ALLOW_UNFREE=1

# starts a shell with Goland (`jetbrains.goland`) and latest Golang (`go`) installed
nix-shell -p jetbrains.goland go

# Optional: change to your preferred shell
zsh

# Inside the shell, start the remote-dev-server
"$(dirname $(which goland))"/../goland-2021.3.2/bin/remote-dev-server.sh run .
```
