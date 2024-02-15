{
  lib,
  config,
  ...
}: let
  cfg = config.home.catppuccin;
in
  with lib; {
    options.home.catppuccin = {
      variant = lib.mkOption {
        type = types.str;
        default = "mocha";
      };
      accent = lib.mkOption {
        type = types.str;
        default = "blue";
      };
      size = lib.mkOption {
        type = types.str;
        default = "compact";
      };
      tweak = lib.mkOption {
        type = types.str;
        default = "nord";
      };
      flavor = lib.mkOption {
        type = types.str;
        default = "${cfg.variant}";
      };
    };
  }
