{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];
  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
      # {
      #   name = "flathub-beta";
      #   location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
      # }
    ];
    packages = [
    ];
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
  xdg = {
    portal = {
      enable = true;
      extraPortals = lib.mkDefault [
        pkgs.kdePackages.xdg-desktop-portal-kde
        pkgs.xdg-desktop-portal-gtk
      ];
    };
    icons.enable = true;
    sounds.enable = true;
  };

  systemd.user.extraConfig = ''
    DefaultEnvironment="PATH=/run/current-system/sw/bin"
  '';

  # Flatpak applications cannot follow symlinks to the nix store, so we create bindmounts to resolve them transparently
  system.fsPackages = [ pkgs.bindfs ];
  fileSystems = {
    # Create an FHS mount to support flatpak host icons/fonts/wtv
    #"/usr/share/applications" = mkRoSymBind (config.system.path + "/share/applications");
    # "/usr/share/icons" = lib.mkIf config.xdg.icons.enable (
    #   mkRoSymBind (config.system.path + "/share/icons")
    # );
    # "/usr/share/fonts" = mkRoSymBind (aggregatedFonts + "/share/fonts");
  };
}
