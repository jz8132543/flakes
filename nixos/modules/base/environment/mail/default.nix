{ lib, ... }:
with lib;
{
  options.environment = {
    smtp_host = lib.mkOption {
      type = types.str;
      default = "glacier.mxrouting.net";
      description = "";
    };
    smtp_port = lib.mkOption {
      type = types.port;
      default = 465;
      description = "";
    };
  };
}
