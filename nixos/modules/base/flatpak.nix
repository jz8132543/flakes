{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  isDesktop =
    config.services.xserver.enable
    || config.services.desktopManager.plasma6.enable
    || config.services.gnome.core-shell.enable;
in
{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];
  services.flatpak = {
    # 仅在桌面模式下默认开启 Flatpak，服务器默认关闭以节省空间
    enable = lib.mkDefault isDesktop;
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    packages = [ ];
    # 自动更新
    update.onActivation = true;
    # 自动移除未声明的 Flatpak 包 (保持系统纯净)
    uninstallUnmanaged = true;
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # https://github.com/abread/nixconfig/blob/3aca60ffb13c1d54cf962698deeed8d0c608f8b8/profiles/pc/flatpak.nix
  xdg.portal = lib.mkIf config.services.flatpak.enable {
    enable = true;
    extraPortals = lib.mkDefault (
      if isDesktop then
        [
          pkgs.kdePackages.xdg-desktop-portal-kde
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-gnome
        ]
      else
        [
          # 如果在服务器上手动开启了 Flatpak，至少需要一个基本的 Portal 满足强制性断言
          pkgs.xdg-desktop-portal-gtk
        ]
    );
    config.common.default = "*";
  };

  xdg.icons.enable = lib.mkDefault isDesktop;
  xdg.sounds.enable = lib.mkDefault isDesktop;

  systemd.user.extraConfig = lib.mkIf config.services.flatpak.enable ''
    DefaultEnvironment="PATH=/run/current-system/sw/bin"
  '';

  # Flatpak applications cannot follow symlinks to the nix store, so we create bindmounts to resolve them transparently
  system.fsPackages = lib.mkIf config.services.flatpak.enable [ pkgs.bindfs ];
}
