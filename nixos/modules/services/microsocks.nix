{
  config,
  lib,
  ...
}:

let
  cfg = config.services.custom-microsocks;
in
{
  options.services.custom-microsocks = {
    enable = lib.mkEnableOption "Custom Microsocks SOCKS5 Proxy with Mihomo bypass rules";
  };

  config = lib.mkIf cfg.enable {
    services.microsocks = {
      enable = true;
      ip = "0.0.0.0";
    };

    # 1. Create a dedicated microsocks user and group with a fixed UID
    users.users.microsocks = {
      isSystemUser = true;
      group = "microsocks";
      uid = 999;
      description = "User for microsocks proxy (fixed UID for mihomo bypass)";
    };
    users.groups.microsocks = {
      gid = 999;
    };

    # 2. Configure microsocks systemd service to use the fixed user
    systemd.services.microsocks = {
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "microsocks";
        Group = "microsocks";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 1080 ];
  };
}
