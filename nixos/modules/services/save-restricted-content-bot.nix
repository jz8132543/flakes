# Save Restricted Content Bot module
# 策略：MongoDB 原生 NixOS 服务，Bot 运行于 Podman 容器中
# 镜像由 systemd oneshot 从 Nix store 中的源码构建
{
  config,
  lib,
  pkgs,
  nixosModules,
  ...
}:
let
  cfg = config.services.save-restricted-content-bot;
  botSrc = pkgs.save-restricted-content-bot;
  imageTag = "localhost/save-restricted-content-bot:${botSrc.version}";
in
{
  imports = [ nixosModules.services.podman ];

  options.services.save-restricted-content-bot = {
    enable = lib.mkEnableOption "Save Restricted Content Bot service" // {
      default = true;
    };

    loginSystem = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable user interactive login system (via Telegram /login command).
        Default is true, ensuring seamless, zero-maintenance out-of-the-box startup
        on any server without fragile static user string sessions.
        If set to false, the bot will use STRING_SESSION from sops secrets.
      '';
    };

    waitingTime = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Waiting time in seconds between batch items to prevent FloodWait.";
    };

    errorMessage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to send verbose error messages to chat.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── MongoDB (使用预编译容器镜像替代源码编译) ──────────────────────────────────────────
    # 避免在低配服务器上从源码编译 MongoDB 导致内存溢出 (OOM)
    virtualisation.oci-containers.containers.mongodb = {
      image = "docker.io/library/mongo:7.0";
      extraOptions = [ "--network=host" ];
      volumes = [ "mongodb_data:/data/db" ];
    };

    # ── 构建容器镜像 (oneshot) ───────────────────────────────────────────────
    # 只在镜像不存在时才构建，源码版本变更时 tag 变化会触发重建
    systemd.services.podman-build-save-restricted-content-bot = {
      description = "Build Save Restricted Content Bot container image using Podman";
      before = [ "podman-save-restricted-content-bot.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "build-bot-image" ''
          if ! ${pkgs.podman}/bin/podman image exists ${imageTag}; then
            echo "Building image ${imageTag} from ${botSrc}..."
            ${pkgs.podman}/bin/podman build \
              --tag ${imageTag} \
              --file ${botSrc}/Dockerfile \
              ${botSrc}
          else
            echo "Image ${imageTag} already exists, skipping build."
          fi
        '';
      };
    };

    # ── 运行容器 ─────────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers.save-restricted-content-bot = {
      image = imageTag;
      # 使用 host 网络，容器内可直连 127.0.0.1:27017 的 MongoDB
      # --pull=never 严禁 podman 尝试从外部 registry (localhost) 拉取本地构建的镜像
      extraOptions = [
        "--network=host"
        "--pull=never"
      ];
      # 从 sops template 注入环境变量
      environmentFiles = [
        config.sops.templates."save-restricted-content-bot".path
      ];
      dependsOn = [ "mongodb" ]; # podman 会自动确保 mongodb 容器先启动
    };

    # 确保容器服务在启动前镜像必然存在，并等待 sops secrets 与依赖服务就绪
    systemd.services.podman-save-restricted-content-bot = {
      preStart = ''
        if ! ${pkgs.podman}/bin/podman image exists ${imageTag}; then
          echo "Image ${imageTag} not found locally, building from ${botSrc}..."
          ${pkgs.podman}/bin/podman build \
            --tag ${imageTag} \
            --file ${botSrc}/Dockerfile \
            ${botSrc}
        fi
      '';
      after = [
        "podman-build-save-restricted-content-bot.service"
        "podman-mongodb.service"
        "sops-install-secrets.service"
        "network-online.target"
      ];
      requires = [
        "podman-mongodb.service"
        "sops-install-secrets.service"
      ];
    };

    # ── sops secrets ─────────────────────────────────────────────────────────
    sops.secrets = {
      "telegram/api_id" = { };
      "telegram/api_hash" = { };
      "telegram/save_token" = { };
      "telegram/string_session" = { };
      "telegram/userid" = { };
      "telegram/save_restricted_channelid" = { };
    };

    # mode=0444 — DynamicUser 容器进程也可读
    sops.templates."save-restricted-content-bot" = {
      mode = "0444";
      content = ''
        LOGIN_SYSTEM=${if cfg.loginSystem then "true" else "false"}
        STRING_SESSION=${if cfg.loginSystem then "" else config.sops.placeholder."telegram/string_session"}
        API_HASH=${config.sops.placeholder."telegram/api_hash"}
        API_ID=${config.sops.placeholder."telegram/api_id"}
        BOT_TOKEN=${config.sops.placeholder."telegram/save_token"}
        ADMINS=${config.sops.placeholder."telegram/userid"}
        CHANNEL_ID=${config.sops.placeholder."telegram/save_restricted_channelid"}
        DB_URI=mongodb://127.0.0.1:27017
        WAITING_TIME=${toString cfg.waitingTime}
        ERROR_MESSAGE=${if cfg.errorMessage then "true" else "false"}
      '';
    };
  };
}
