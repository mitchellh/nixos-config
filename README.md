![Screenshot](https://raw.githubusercontent.com/mitchellh/nixos-config/main/.github/images/screenshot.png)

## Installation and features

Visit https://smallstepman.github.io/

This repository is now den-native: hosts are declared in `den/hosts.nix`, and
platform/user behavior is composed from `den/aspects/...`.

Study install scripts in `docs/` dir. 

For detailed walktrough, visit upstream repo.

## Acknoledgment

I forked it from here: https://github.com/mitchellh/nixos-config

I'm forever grateful.

> This repository contains my NixOS system configurations. This repository
> isn't meant to be a turnkey solution to copying my setup or learning Nix,
> so I want to apologize to anyone trying to look for something "easy". I've
> tried to use very simple Nix practices wherever possible, but if you wish
> to copy from this, you'll have to learn the basics of Nix, NixOS, etc.

is what the author of the upstream wrote in his README, but I think he underestimated his craft, as it indeed did turned out to be a turnkey and easily customizable Nix config. Needless to say, my LLM agents loved it.

> I don't claim to be an expert at Nix or NixOS, so there are certainly
> improvements that could be made! Feel free to suggest them, but please don't
> be offended if I don't integrate them, I value having my config work over
> having it be optimal.

based. same.

## Why

I had HPs, DELLs, ThinkPads (❤️🔴), but Apple hardware is simply superior. 
However the WM/DE part of MacOS suckkkks soOoOoOoO much, don't get me started. 
So, I want a productive OS, and nothing ever surpassed my Arch/i3/doomemacs 
config in terms of how quickly I could do things. I loved playing with Arch, 
but I hated managing it, especially when I had to move machines (which will 100% 
happen again, unless bus factor), so: NixOS-in-VM-on-Macbook-with-nix-darwin. 

Yes, Nix is very good. Of course I got helplessy addicted the moment I touched it, and 
immediately started schememing how to install it on every single electricity-powerd thing I own.

Yes, VM is fast enough. Yes, it has an impact on the battery, and for this reason, I will 
maintain feature parity between MacOS and VM (in case I need to work while traveling etc). 
Below table shows time it took to discharge 25% of the battery:
|CPU load|VM on|VM off|
|-|-|-|
|0%|-|-|
|100%|-|-|

I enjoy using macOS for the graphical applications (browser, calendars, mail app, 
iMessage, Music etc.), LMStudio (MLX acceleratation available via native bindings), 
and running Docker (virtualizing it is wasteful when I can do passtrough instead).

### Docker: single daemon on macOS, used from the VM

Docker Desktop runs **only on macOS** — there is no Docker daemon inside the VM.
The VM reaches the host daemon over SSH via a Docker context named `host-mac`
(endpoint `ssh://m@mac-host-docker`, which resolves to the VMware host-only
interface at `192.168.130.1`).  `DOCKER_CONTEXT=host-mac` is exported
automatically in the VM shell so every `docker` command is transparently
forwarded to the host daemon.

**SSH key provisioning:** the VM authenticates to the macOS host using the
host's normal `~/.ssh/id_ed25519` key inside the VM. The matching public key is
stored in the external generated dataset (`~/.local/share/nix-config-generated`
on macOS, exposed to the VM as `/nixos-generated`) and deployed to the macOS
host's `~/.ssh/authorized_keys` by the Darwin host aspects. No separate
VM-specific key is needed.

**Bind-mount constraint:** because the daemon lives on macOS, bind-mount source
paths are resolved on the **macOS host**, not on the VM.  Project files that
need to be bind-mounted must live under `/Users/m/Projects` (the directory
shared from macOS into the VM via VMware Shared Folders).

**Diagnosing bind-mount failures:** prefer `--mount type=bind,src=…,dst=…`
over the short `-v` flag.  With `--mount`, Docker errors immediately when the
source path does not exist on the host; with `-v` it silently auto-creates the
missing directory, which hides misconfigured paths.
