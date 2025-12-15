# Gnome with ibus
{ lib, pkgs, ... }: {
  specialisation."gnome-ibus".configuration = {
    services.xserver = {
      enable = true;
      xkb.layout = "us";
    };
    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = true;

    i18n.inputMethod = lib.mkForce {
      enable = true;
      type = "ibus";
      ibus.engines = with pkgs; [
        # None yet
      ];
    };
  };
}
