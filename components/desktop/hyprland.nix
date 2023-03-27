{ self, config, pkgs, lib, ... }:

{
  imports = [
    self.nixosModules.hyprland
  ];
  #security.polkit.enable = true;
  xdg.portal.enable = true;
  services = {
    logind.lidSwitch = "ignore";
    greetd = {
      enable = true;
      package = pkgs.greetd.tuigreet;
      settings = {
        default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd ${pkgs.hyprland}/bin/Hyprland";
      };
    };
  };
  services.xserver.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = "tippy";
    defaultSession = "${pkgs.hyprland}/bin/Hyprland";
  };
  programs.hyprland = {
    enable = true;
    # xwayland = {
    #   enable = true;
    #   hidpi = true;
    # };
    nvidiaPatches = false;
  };
}
