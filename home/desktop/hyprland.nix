{ pkgs, inputs, ... }:

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
  home.file.".config/rofi".source = "${inputs.hyprland-config}/dots/rofi";
  home.file.".config/wofi".source = "${inputs.hyprland-config}/dots/wofi";
  home.file.".config/kitty".source = "${inputs.hyprland-config}/dots/kitty";
  home.file.".config/dunst".source = "${inputs.hyprland-config}/dots/dunst";
  home.file.".config/hypr" = {
    source = inputs.hyprland-config;
    recursive = true;
  };
  home.file.".config/hypr/hyprpaper.conf".text = ''
    preload = ~/.config/hypr/themes/apatheia/wallpapers/Sakura.png
    wallpaper = eDP-1,~/.config/hypr/themes/apatheia/wallpapers/Sakura.png
  '';
  home.file.".config/hypr/hyprland.conf".text = ''
    exec-once=sudo ln -s /run/current-system/sw/bin/bash /bin/bash
    bind=SUPER,0,workspace,0
    bind=ALT,0,movetoworkspace,0
    source=~/.config/hypr/_hyprland.conf
    input {
      kb_options=caps:swapescape,caps:escape
      touchpad {
        natural_scroll = true
      }
    }
    exec-once=~/.config/hypr/scripts/variables/set_env background ~/.config/hypr/themes/apatheia/wallpapers/Sakura.png
    exec-once=~/.config/hypr/themes/apatheia/scripts/wallpaper
    exec-once=~/.config/hypr/scripts/variables/set_env primary 1
    exec-once=fcitx5 -d
    exec-once=kanshi
    exec-once=hyprpaper
  '';
  home.packages = with pkgs;[
    kanshi
  ];
}
