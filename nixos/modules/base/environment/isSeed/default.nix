{ lib, ... }:
with lib;
{
  options.environment.isSeed = lib.mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to enable seed mode (e.g. limit qBittorrent upload speed).
    '';
  };
}
