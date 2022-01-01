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

- Delete SSH key from knonw_hosts `ssh-keygen -R 192.168.100.131`

## Resources

- [Cheatsheet](https://nixos.wiki/wiki/Cheatsheet)
- [Flakes](https://nixos.wiki/wiki/Flakes)
- [Practical Nix Flakes](https://serokell.io/blog/practical-nix-flakes)
- [NixOS Home Manager for multi-user on NIX flake Installation and Configuration](https://mudrii.medium.com/nixos-home-manager-on-native-nix-flake-installation-and-configuration-22d018654f0c)
- [Collection of NixOS](https://wiki.nikitavoloboev.xyz/operating-systems/linux/nixos)
- [agenix - age-encrypted secrets for NixOS](https://github.com/ryantm/agenix)

https://nixos.mayflower.consulting/blog/2021/01/28/nextcloud-stateversion/

https://releases.nixos.org/?prefix=nixos/21.05-small/nixos-21.05.3915.95eed9b64ee/

https://www.reddit.com/r/NixOS/comments/fsummx/how_to_list_all_installed_packages_on_nixos/
