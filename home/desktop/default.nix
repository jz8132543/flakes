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
  home.packages = with pkgs; [
    rofi
    swaynotificationcenter
    brave
    kanshi
  ];
}
