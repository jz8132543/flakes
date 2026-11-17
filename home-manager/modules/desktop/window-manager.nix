{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.window-manager = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Shared tools and appearance for standalone Wayland compositors.";
    };
    sessionTarget = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = "Compositor target owning the standalone desktop services.";
    };
    polkit.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run a standalone authentication agent unless the selected shell supplies one.";
    };
  };

  config = lib.mkIf config.window-manager.enable {
    home.packages = with pkgs; [
      wl-clipboard
      cliphist
      grim
      slurp
      satty
      nautilus
    ];
    # Shells may own clipboard history, notifications, authentication and locking.
    # Tools stay available without automatically starting competing watchers.
    systemd.user.services.window-manager-polkit = lib.mkIf config.window-manager.polkit.enable {
      Unit = {
        Description = "Wayland graphical authentication agent";
        PartOf = [ config.window-manager.sessionTarget ];
        After = [ config.window-manager.sessionTarget ];
      };
      Service = {
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
      };
      Install.WantedBy = [ config.window-manager.sessionTarget ];
    };
    gtk = {
      enable = true;
      theme = {
        name = "MacTahoe-Light-solid";
        package = pkgs.mactahoe.gtk;
      };
      iconTheme = {
        name = "MacTahoe-light";
        package = pkgs.mactahoe.icons;
      };
      gtk3.extraConfig.gtk-application-prefer-dark-theme = false;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = false;
    };
    home.pointerCursor = {
      enable = true;
      name = "MacTahoe-cursors";
      package = pkgs.mactahoe.cursors;
      size = 24;
      gtk.enable = true;
    };
    dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-light";
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "inode/directory" = lib.mkForce [ "org.gnome.Nautilus.desktop" ];
        "x-scheme-handler/terminal" = [ "kitty.desktop" ];
      };
    };
    xdg.terminal-exec = {
      enable = true;
      settings.default = [ "kitty.desktop" ];
    };
  };
}
