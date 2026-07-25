{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.kaogong-helper;
in
{
  options.services.kaogong-helper = {
    enable = lib.mkEnableOption "Civil Service Exam Prep System (考公备考辅助系统)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kaogong-helper;
      description = "The kaogong-helper package to run";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7070;
      description = "Port to listen on";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host IP to bind to";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the port in the firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ cfg.port ];

    users.users.kaogong-helper = {
      isSystemUser = true;
      group = "kaogong-helper";
      description = "Kaogong Helper service user";
    };
    users.groups.kaogong-helper = { };

    systemd.services.kaogong-helper = {
      description = "Civil Service Exam Prep System Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
        HOST = cfg.host;
      };

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/kaogong-helper";
        User = "kaogong-helper";
        Group = "kaogong-helper";
        Restart = "always";
        RestartSec = "5s";
        ProtectSystem = "full";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };

    services.traefik.proxies.kaogong = {
      rule = "Host(`kaogong.${config.networking.domain}`)";
      target = "http://${cfg.host}:${toString cfg.port}";
    };
  };
}
