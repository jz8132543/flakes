{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.steam;
in {
  options.programs.steam = {
    hidpi = {
      enable = lib.mkEnableOption "steam hidpi desktop item";
      scale = lib.mkOption {
        type = lib.types.str;
        default = "2";
      };
    };
  };

  config = lib.mkMerge [
    {
      programs.steam.enable = true;
      environment.global-persistence.user.directories = [
        ".steam"
        ".local/share/Steam"
      ];
      # require out-of-tree kernel module
      # hardware.xpadneo.enable = true;
    }
    (lib.mkIf cfg.hidpi.enable {
      environment.systemPackages = [
        (pkgs.makeDesktopItem {
          name = "stream-hidpi";
          desktopName = "Steam (HiDPI)";
          exec = "env GDK_SCALE=\"${cfg.hidpi.scale}\" steam %U";
          categories = [
            "Game"
          ];
          icon = "steam";
        })
      ];
    })
  ];
}
