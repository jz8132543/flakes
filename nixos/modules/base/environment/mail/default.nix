{ lib, ... }:
with lib;
{
  options.environment.smtp_host = lib.mkOption {
    type = types.str;
    default = "glacier.mxrouting.net";
    description = '''';
  };
}
