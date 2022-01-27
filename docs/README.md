# Nix & NixOS

## Tips and Tricks

- hashedPassword
```sh
## using brew
brew tap tonidy/tools-tap
brew install mkpasswd
mkpasswd -m sha-512 "root" # Invalid method

## using docker
docker run --rm -it flyinprogrammer/mkpasswd -m sha-512 root
$6$RGtlrdlYYMi$l8C5yMP96ySm.xxRcWZnNZRhf.ApXHkWwhWhk8X87S7VCQrEe9YCLQn1hezH.qUHUn7VLiJc75zxs.4Nl3TG51
```

- Delete SSH key from knonw_hosts `ssh-keygen -R 192.168.100.xxx`

## Resources

- [Cheatsheet](https://nixos.wiki/wiki/Cheatsheet)
- [Generations](https://nixos.wiki/wiki/NixOS#Generations)
- **[How to Learn Nix](https://ianthehenry.com/posts/how-to-learn-nix/)**
- [Collection of NixOS](https://wiki.nikitavoloboev.xyz/operating-systems/linux/nixos)
- [agenix - age-encrypted secrets for NixOS](https://github.com/ryantm/agenix)
- [VS Code Remote Containers with Nix](https://levelup.gitconnected.com/vs-code-remote-containers-with-nix-2a6f230d1e4e)
- *[Nix Flakes](https://www.yanboyang.com/nixflakes/)*
- *[An introduction to nix-shell](https://ghedam.at/15978/an-introduction-to-nix-shell)*
- *[A Tour of Nix Flakes](https://ghedam.at/a-tour-of-nix-flakes)*
- *[Novice Nix: Flake Templates](https://peppe.rs/posts/novice_nix:_flake_templates/)*
- [What Is Nix and How to Use It?](https://typeable.io/blog/2021-04-19-nix-intro)
- **[NixOS: For developers](https://myme.no/posts/2020-01-26-nixos-for-development.html)**
- [TWEAG NIX Blog](https://www.tweag.io/blog/tags/nix)
- **[NIX FLAKES, PART 1: AN INTRODUCTION AND TUTORIAL](https://www.tweag.io/blog/2020-05-25-flakes/)**
- **[NIX FLAKES, PART 2: EVALUATION CACHING](https://www.tweag.io/blog/2020-06-25-eval-cache/)**
- **[NIX FLAKES, PART 3: MANAGING NIXOS SYSTEMS](https://www.tweag.io/blog/2020-07-31-nixos-flakes/)**
- [Flakes](https://nixos.wiki/wiki/Flakes)
- [Practical Nix Flakes](https://serokell.io/blog/practical-nix-flakes)
- [NixOS Home Manager for multi-user on NIX flake Installation and Configuration](https://mudrii.medium.com/nixos-home-manager-on-native-nix-flake-installation-and-configuration-22d018654f0c)



https://nixos.mayflower.consulting/blog/2021/01/28/nextcloud-stateversion/

https://releases.nixos.org/?prefix=nixos/21.05-small/nixos-21.05.3915.95eed9b64ee/

https://www.reddit.com/r/NixOS/comments/fsummx/how_to_list_all_installed_packages_on_nixos/
