# Gnome with ibus
{ lib, pkgs, ... }: {
  specialisation."gnome-ibus".configuration = {
    services.xserver = {
      enable = true;
      xkb.layout = "us";
      desktopManager.gnome.enable = true;
      displayManager.gdm.enable = true;
    };

    i18n.inputMethod = lib.mkForce {
      enable = true;
      type = "ibus";
      ibus.engines = with pkgs; [
        # None yet
      ];
    };
  };
}
