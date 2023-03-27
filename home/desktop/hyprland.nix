{ pkgs, ... }:

{
  home.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    GDK_BACKEND = "wayland";
    _JAVA_AWT_WM_NONREPARENTING = 1;
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
  };
  programs.zsh = {
    loginExtra = ''
      # If running from tty1 start hyprland
      if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
        Hyprland
      fi
    '';
  };
  home.file.".config/hypr/hyprland.conf".source = ./hyprland.conf;
  services = {
    kanshi = {
      enable = true;
      profiles = {
        dockd = {
          outputs = [
            {
              criteria = "eDP-1";
              position = "3240,2160";
              scale = 2.0;
              mode = "3240x2160";
            }
          ];
        };
      };
    };
  };
  home.packages = with pkgs; [
    swaynotificationcenter
    brave
    kanshi
    kitty
  ];
}
