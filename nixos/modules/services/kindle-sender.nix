{
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.kindle-sender;
  workingDir = "/var/lib/kindle-sender";
  configFile = "${workingDir}/kindle.conf";

  mkService = name: cmd: {
    description = "Kindle Sender - ${name}";
    after = [
      "network.target"
      "rabbitmq.service"
      "redis.service"
    ];
    requires = [
      "rabbitmq.service"
      # "redis.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "kindle-sender";
      Group = "kindle-sender";
      WorkingDirectory = workingDir;
      ExecStart = cmd;
      Environment = [
        "BIND_ADDR=0.0.0.0"
        "PORT=5050"
        "FORCE_443=0"
      ];
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      Restart = "always";
      RestartSec = "10s";
    };
  };
in
{
  options.services.kindle-sender = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable Kindle Sender Bot service";
    };
  };

  config = lib.mkIf cfg.enable {
    services.rabbitmq.enable = true;
    # services.redis.servers."".enable = true;

    # Users and Groups
    users.users.kindle-sender = {
      isSystemUser = true;
      group = "kindle-sender";
      home = workingDir;
      createHome = true;
    };
    users.groups.kindle-sender = { };

    # Systemd Services
    systemd.services.kindle-sender-init = {
      description = "Initialize Kindle Sender DB";
      before = [
        "kindle-sender-bot.service"
        "kindle-sender-worker-fast.service"
        "kindle-sender-worker-slow.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "kindle-sender";
        Group = "kindle-sender";
        WorkingDirectory = workingDir;
        ExecStartPre = pkgs.writeShellScript "prep-kindle-sender" ''
          mkdir -p ${workingDir}/files
          cp ${config.sops.templates."kindle.conf".path} ${configFile}
          chmod 600 ${configFile}
          ln -sfn ${pkgs.send2kindlebot}/lib/send2kindlebot/i18n ${workingDir}/i18n
          # Link python scripts so they can find each other
          find ${pkgs.send2kindlebot}/lib/send2kindlebot -maxdepth 1 -name "*.py" -exec ln -sfn {} ${workingDir}/ \;
        '';
        ExecStart = "${pkgs.send2kindlebot}/bin/send2kindlebot-create-db";
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.kindle-sender-bot = mkService "Bot" "${pkgs.send2kindlebot}/bin/send2kindlebot-bot";
    systemd.services.kindle-sender-worker-fast = mkService "Worker Fast" "${pkgs.send2kindlebot}/bin/send2kindlebot-send Send2KindleBotFast";
    systemd.services.kindle-sender-worker-slow = mkService "Worker Slow" "${pkgs.send2kindlebot}/bin/send2kindlebot-send Send2KindleBotSlow";

    # sops secrets
    sops.secrets = {
      "kindle-sender/username" = { };
      "kindle-sender/password" = { };
      "kindle-sender/token" = { };
      "kindle-sender/chat-id" = { };
    };

    sops.templates."kindle.conf" = {
      owner = "kindle-sender";
      content = ''
        [DEFAULT]
        TOKEN = ${config.sops.placeholder."kindle-sender/token"}
        logfile = ${workingDir}/bot.log
        # Optional path to TLS certificate file used by the bot
        CERT =
        # Optional path to TLS private key file used by the bot
        PRIVKEY =
        # Comma-separated list of blocked senders (optional)
        BLOCKED =
        MULTIPLIER = 2
        DEMO = 3
        ADMIN = ${config.sops.placeholder."kindle-sender/chat-id"}

        [SQLITE3]
        data_base = ${workingDir}/kindle.db
        table = usuarios

        [RABBITMQ]
        CONNECTION_STRING = amqp://guest:guest@localhost:5672/

        [SMTP]
        HOST = glacier.mxrouting.net
        PORT = 465
        USER = ${config.sops.placeholder."kindle-sender/username"}
        PASS = ${config.sops.placeholder."kindle-sender/password"}
      '';
    };
  };
}
