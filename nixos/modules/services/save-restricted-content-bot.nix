# Save Restricted Content Bot module
# 策略：MongoDB 原生 NixOS 服务，Bot 运行于 Podman 容器中
# 镜像由 systemd oneshot 从 Nix store 中的源码构建
{
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  # 镜像 tag 包含源码版本，源码更新时自动触发重建
  botSrc = pkgs.save-restricted-content-bot;
  imageTag = "localhost/save-restricted-content-bot:${botSrc.version}";
in
{
  imports = [ nixosModules.services.podman ];

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
    description = "Build Save Restricted Content Bot container image";
    # 必须在容器服务启动前完成
    before = [ "podman-save-restricted-content-bot.service" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
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
    extraOptions = [ "--network=host" ];
    # 从 sops template 注入环境变量
    environmentFiles = [
      config.sops.templates."save-restricted-content-bot".path
    ];
    # 覆盖 Dockerfile 中硬编码的 -p 5000，强制读取环境变量中的 PORT
    cmd = [
      "sh"
      "-c"
      "flask run -h 0.0.0.0 -p \${PORT:-5000} & python3 main.py"
    ];
    dependsOn = [ "mongodb" ]; # podman 会自动确保 mongodb 容器先启动
  };

  # 确保容器服务在镜像构建完成后才启动
  systemd.services.podman-save-restricted-content-bot = {
    after = [
      "podman-build-save-restricted-content-bot.service"
      "podman-mongodb.service"
    ];
    requires = [
      "podman-build-save-restricted-content-bot.service"
      "podman-mongodb.service"
    ];
  };

  # ── sops secrets ─────────────────────────────────────────────────────────
  sops.secrets = {
    "telegram/save_token" = { };
    "telegram/userid" = { };
    "telegram/save_restricted_channelid" = { };
    "telegram/api_id" = { };
    "telegram/api_hash" = { };
  };

  # mode=0444 — DynamicUser 容器进程也可读
  sops.templates."save-restricted-content-bot" = {
    mode = "0444";
    content = ''
      BOT_TOKEN=${config.sops.placeholder."telegram/save_token"}
      API_ID=${config.sops.placeholder."telegram/api_id"}
      API_HASH=${config.sops.placeholder."telegram/api_hash"}
      OWNER_ID=${config.sops.placeholder."telegram/userid"}
      FORCE_SUB=${config.sops.placeholder."telegram/save_restricted_channelid"}
      MONGO_DB=mongodb://127.0.0.1:27017
      DB_NAME=save_restricted_content_bot
      PORT=5001
    '';
  };
}
