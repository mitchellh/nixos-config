# NixOS System Configurations

This repository contains my NixOS system configurations. This repository
isn't meant to be a turnkey solution to copying my setup or learning Nix,
so I want to apologize to anyone trying to look for something "easy". I've
tried to use very simple Nix practices wherever possible, but if you wish
to copy from this, you'll have to learn the basics of Nix, NixOS, etc.

I don't claim to be an expert at Nix or NixOS, so there are certainly
improvements that could be made! Feel free to suggest them, but please don't
be offended if I don't integrate them, I value having my config work over
having it be optimal.

## How I Work

I like to use macOS as the host OS and NixOS within a VM as my primary
development environment. I use the graphical applications on the host
(browser, calendars, mail app, iMessage, etc.) but I do almost everything
dev-related in the VM (editor, compilation, databases, etc.).

Inevitably I get asked **why?** I genuinely like the macOS application
ecosystem, and I'm pretty "locked in" to their various products such as
iMessage. I like the Apple hardware, and I particularly like that my hardware
always Just Works with excellent performance, battery life, and service.
However, I prefer the Linux environment for almost all my dev work. I find
that modern computers are plenty fast enough for the best of both worlds.

Here is what it ends up looking like:

![Screenshot](https://raw.githubusercontent.com/mitchellh/nixos-config/main/.github/images/screenshot.png)

Note that I usually full screen the VM so there isn't actually a window,
and I three-finger swipe or use other keyboard shortcuts to active that
window.

### Common Questions Related To This Workflow

**How does web application development work?** I use the VM's IP. Even
though it isn't strictly static, it never changes since I rarely run
other VMs. You just have to make sure software in the VM listens
on `0.0.0.0` so that it isn't only binding to loopback.

**Does copy/paste work?** Yes.

**Do you use shared folders?** I set up a shared folder so I can access
the home directory of my host OS user, but I very rarely use it. I primarily
only use it to access browser downloads. You can see this setup in these
Nix files.

**Do you ever launch graphical applications in the VM?** Sometimes, but rarely.
I'll sometimes do OAuth flows and stuff using FireFox in the VM. Most of the
time, I use the host OS browser.

**Do you have graphical performance issues?** Graphical applications can
have framerate issues, particularly animation. I try to avoid doing any of
this in the VM and only do terminal UIs. Terminal workflows have no performance
issues ever.

**This can't actually work! This only works on a powerful workstation!**
I've been doing this for almost  2 years now, and I've developed
[a lot of very real software](https://www.hashicorp.com/). It works for me.
I also use this VM on a MacBook Pro (to be fair, it is maxed out on specs),
and I have no issues whatsoever.

**Does this work with Apple Silicon Macs?** Yes, I use VMware Fusion
but my configurations also work for Parallels and UTM. Folder syncing,
clipboards, and graphics acceleration all work. I've been using an
Apple Silicon Mac full time since Nov 2021 with this setup.

## Setup (VM)

Video: https://www.youtube.com/watch?v=ubDMLoWz76U

**Note:** This setup guide will cover VMware Fusion because that is the
hypervisor I use day to day. The configurations in this repository also
work with UTM (see `vm-aarch64-utm`) and Parallels (see `vm-aarch64-prl`) but
I'm not using that full time so they may break from time to time.

You can also download NixOS ISOs from [Hydra](https://hydra.nixos.org/project/nixos),
including aarch64 ISOs.

Create a VMware Fusion VM with the following settings. My configurations
are made for VMware Fusion exclusively currently and you will have issues
on other virtualization solutions without minor changes.

  * ISO: NixOS 22.11 or later.
  * Disk: NVMe 150 GB+
  * CPU/Memory: I give at least half my cores and half my RAM, as much as you can.
  * Graphics: Full acceleration, full resolution, maximum graphics RAM.
  * Network: Shared with my Mac.
  * Remove sound card, remove video camera.
  * Profile: Disable almost all keybindings

Boot the VM, and using the graphical console, change the root password to "root":

```
$ sudo su
$ passwd
# change to root
```

At this point, verify `/dev/nvme0n1` exists. This is the expected block device
where the Makefile will install the OS. If you setup your VM to use NVMe,
this should exist. If `/dev/sda` or `/dev/vda` exists instead, you didn't
configure NVMe properly. Note, these other block device types work fine,
but you'll probably have to modify the `bootstrap0` Makefile task to use
the proper block device paths.

Run `ifconfig` and get the IP address of the first device. It is probably
`192.168.58.XXX`, but it can be anything. In a terminal with this repository
set this to the `NIXADDR` env var:

```
$ export NIXADDR=<VM ip address>
```

The Makefile assumes an Intel processor by default. If you are using an
ARM-based processor (M1, etc.), you must change `NIXNAME` so that the ARM-based
configuration is used:

```
$ export NIXNAME=vm-aarch64
```

**Other Hypervisors:** If you are using Parallels, use `vm-aarch64-prl`.
If you are using UTM, use `vm-aarch64-utm`. Note that the environments aren't
_exactly_ equivalent between hypervisors but they're very close and they
all work.

Perform the initial bootstrap. This will install NixOS on the VM disk image
but will not setup any other configurations yet. This prepares the VM for
any NixOS customization:

```
$ make vm/bootstrap0
```

After the VM reboots, run the full bootstrap, this will finalize the
NixOS customization using this configuration:

```
$ make vm/bootstrap
```

You should have a graphical functioning dev VM.

At this point, I never use Mac terminals ever again. I clone this repository
in my VM and I use the other Make tasks such as `make test`, `make switch`, etc.
to make changes my VM.

## Setup (macOS/Darwin)

**THIS IS OPTIONAL AND UNRELATED TO THE VM WORK.** I recommend you ignore
this unless you're interested in using Nix to manage your Mac too.

I share some of my Nix configurations with my Mac host and use Nix
to manage _some_ aspects of my macOS installation, too. This uses the
[nix-darwin](https://github.com/LnL7/nix-darwin) project. I don't manage
_everything_ with Nix, for example I don't manage apps, some of my system
settings, Homebrew, etc. I plan to migrate some of those in time.

To utilize the Mac setup, first install Nix using some Nix installer.
There are two great installers right now:
[nix-installer](https://github.com/DeterminateSystems/nix-installer)
by Determinate Systems and [Flox](https://floxdev.com/). The point of both
for my configs is just to get the `nix` CLI with flake support installed.

Once installed, clone this repo and run `make`. If there are any errors,
follow the error message (some folders may need permissions changed,
some files may need to be deleted). That's it.

**WARNING: Don't do this without reading the source.** This repository
is and always has been _my_ configurations. If you blindly run this,
your system may be changed in ways that you don't want. Read my source!
