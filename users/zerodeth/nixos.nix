{ pkgs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];

  users.users.zerodeth = {
    isNormalUser = true;
    home = "/home/zerodeth";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "$6$XECGl7SdC.v$BxPSgsoFRxE49v.mU0R5j4MEWloixaxiKx43k6SNNzayRWuLl1UuvMARou8.e9fjxDNqChXuzXYKRKn1rRWL41";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjOxtxbn5EivnsfDKeGaappZlcW9SGk81+i4xCZfE+y Sherif Abdalla"
    ];
  };

  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix)
  ];
}
