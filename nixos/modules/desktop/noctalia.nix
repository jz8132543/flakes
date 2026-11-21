{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.noctalia;
in
{
  imports = [ inputs.noctalia.nixosModules.default ];

  options.desktop.noctalia = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Noctalia shell and its native desktop services.";
    };
    sessionTarget = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = "Compositor session target that starts and stops Noctalia.";
    };
    showcase = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use the official showcase desktop and lockscreen preset; disable to restore the previous layout.";
      };
      logicalWidth = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1706;
        description = "Logical output width used to size showcase widgets, before native placement remapping.";
      };
      logicalHeight = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1066;
        description = "Logical output height used to size showcase widgets, before native placement remapping.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.noctalia = {
      enable = true;
      recommendedServices.enable = true;
      systemd = {
        enable = true;
        target = cfg.sessionTarget;
      };
    };
    # Start the tray before applications, not before a target that may already
    # be an ordering prerequisite of the selected compositor session.
    systemd.user.services.noctalia.before = lib.mkForce [ "xdg-desktop-autostart.target" ];

    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    services.upower.enable = true;
    security.polkit.enable = true;
    security.rtkit.enable = true;
    # This also enables login PAM keyring integration, inherited by greetd.
    services.gnome.gnome-keyring.enable = true;
    programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
    programs.dconf.enable = true;

    # Audio must keep working when the optional NectarLink integration is off.
    services.pipewire = {
      enable = true;
      audio.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    fonts.packages = with pkgs; [
      noto-fonts
      inter
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
    ];
    environment.systemPackages = [ pkgs.sound-theme-freedesktop ];
  };
}
