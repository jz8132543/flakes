{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.nextcloud;
  domain = config.networking.domain;
  hostName = "cloud.${domain}";
  inherit (cfg) occ;
in
{
  imports = [
    (import nixosModules.services.office { })
    ./secrets.nix
  ];

  options.services.nextcloud-cluster.core = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Nextcloud Core Service";
    };
    databaseHost = lib.mkOption {
      type = lib.types.str;
      default = PG;
      description = "PostgreSQL database host.";
    };
  };

  config = lib.mkIf config.services.nextcloud-cluster.core.enable {
    # ── 目录权限 ─────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d '${config.users.users.nextcloud.home}/' 0700 nextcloud nextcloud - -"
      "Z '${config.users.users.nextcloud.home}/' 0700 nextcloud nextcloud - -"
    ];

    # ── Nextcloud 主服务配置 ─────────────────────────────────────
    services.nextcloud = {
      enable = true;
      inherit hostName;
      https = true;
      enableImagemagick = true;
      appstoreEnable = true;
      maxUploadSize = "10G";
      configureRedis = true;
      database.createLocally = true;

      config = {
        dbtype = "pgsql";
        dbhost = config.services.nextcloud-cluster.core.databaseHost;
        adminuser = "i";
        adminpassFile = config.sops.secrets."password".path;
      };

      settings = {
        "overwrite.cli.url" = "https://${hostName}/";
        "upgrade.disable-web" = true;
        allow_local_remote_servers = true;
        maintenance_window_start = 2;
        default_phone_region = "CN";
        onlyoffice = {
          DocumentServerUrl = "https://office.${domain}/";
          DocumentServerInternalUrl = "http://127.0.0.1:${toString config.ports.office}/";
          StorageUrl = "https://${hostName}/";
        };
      };

      secretFile = config.sops.templates."nextcloud-secret-config".path;

      # ── 推送通知（notify_push）─────────────────────────────────
      notify_push = {
        enable = true;
        bendDomainToLocalhost = true;
        logLevel = "info";
      };

      # ── 应用套件 ──────────────────────────────────────────────
      extraAppsEnable = true;
      extraApps =
        let
          # 补丁 Talk (spreed)：解除前端 WebRTC 硬编码的 1080p 60fps 分辨率与刷新率限制，提升至 8K (7680x4320) 180fps
          spreed-patched = cfg.package.packages.apps.spreed.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              find js/ -type f -name "*.js" -exec sed -i \
                -e 's/\.width\.max),1920/\.width\.max),7680/g' \
                -e 's/\.height\.max),1080/\.height\.max),4320/g' \
                -e 's/\.frameRate\.max),60/\.frameRate\.max),180/g' \
                -e 's/width:{max:1920,ideal:1920/width:{max:7680,ideal:7680/g' \
                -e 's/height:{max:1080,ideal:1080,min:720},frameRate:{max:30,ideal:30/height:{max:4320,ideal:4320,min:720},frameRate:{max:180,ideal:180/g' \
                -e 's/maxFrameRate: *3/maxFrameRate:180/g' \
                {} +
            '';
          });
        in
        with cfg.package.packages.apps;
        {
          inherit onlyoffice;
          spreed = spreed-patched; # Nextcloud Talk（含 8K 180fps 补丁）
          inherit
            # ── 日历 & 联系人（CalDAV/CardDAV）──
            calendar
            contacts
            # ── 生产力 ──
            deck # Trello 风格看板
            tasks # 任务管理（与 Calendar 联动）
            notes # Markdown 笔记
            forms # 问卷 / 表单
            groupfolders # 群组文件夹管理

            # ── 通讯 ──
            mail # Web 邮件客户端（IMAP/SMTP）

            # ── 多媒体 & 知识 ──
            memories # 相册 / 时间线（类 Google Photos）
            news # RSS 阅读器
            cookbook # 菜谱管理
            gpoddersync # 播客同步
            music # 音乐流媒体播放器

            # ── 协同办公 ──
            whiteboard # 实时白板协作
            drawio # 流程图 / 思维导图

            # ── 安全 ──
            twofactor_webauthn # WebAuthn / YubiKey 无密码登录
            end_to_end_encryption # 端对端加密（E2EE 文件夹）

            # ── 智能 & 识别 ──
            recognize # 本地 AI 人脸 / 场景识别（Photos 分类）
            previewgenerator # 缩略图预生成（批量模式下更快）

            # ── 集成 & 自动化 ──
            cospend # 费用分摊

            # ── 认证 ──
            oidc_login # Keycloak OIDC 单点登录
            ;
        };
    };

    # ── 允许访问 VA-API 设备（视频转码）────────────────────────
    systemd.services.phpfpm-nextcloud.serviceConfig = {
      PrivateDevices = lib.mkForce false;
    };

    # ── ffmpeg（视频预览 & Memories 转码）──────────────────────
    environment.systemPackages = with pkgs; [
      ffmpeg
      imagemagick
    ];

    # ── 依赖顺序 ────────────────────────────────────────────────
    systemd.services.nextcloud-setup = {
      after = [
        "postgresql.service"
        "tailscaled.service"
        "redis-nextcloud.service"
      ];
      requires = [
        "redis-nextcloud.service"
      ];
      unitConfig = {
        RequiresMountsFor = [ "/var/lib/nextcloud" ];
      };
      serviceConfig = {
        Restart = lib.mkForce "on-failure";
      };
    };

    users.users.nextcloud.uid = config.ids.uids.nextcloud;

    # ── ONLYOFFICE 自动配置与连接检测（对接 EuroOffice 后端容器）───
    systemd.services.nextcloud-config-onlyoffice = {
      wantedBy = [ "multi-user.target" ];
      after = [
        "nextcloud-setup.service"
        "podman-eurooffice.service"
      ];
      wants = [
        "podman-eurooffice.service"
      ];
      script = ''
        # 等待 eurooffice 容器准备就绪（健康检查）
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -sf http://127.0.0.1:${toString config.ports.office}/healthcheck >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        secret="$(cat ${config.sops.secrets."onlyoffice/jwtSecretFile".path})"
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice DocumentServerUrl --value "https://office.${domain}/"
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice DocumentServerInternalUrl --value "http://127.0.0.1:${toString config.ports.office}/"
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice StorageUrl --value "https://${hostName}/"
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice jwt_secret --value "$secret"
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice defFormats --value '{}'
        ${occ}/bin/nextcloud-occ config:app:set onlyoffice editFormats --value '{"csv":true,"doc":true,"docm":true,"docx":true,"dotm":true,"dotx":true,"odp":true,"ods":true,"odt":true,"potm":true,"potx":true,"ppsm":true,"ppsx":true,"ppt":true,"pptm":true,"pptx":true,"rtf":true,"txt":true,"xls":true,"xlsb":true,"xlsm":true,"xlsx":true,"xltm":true,"xltx":true}'
        ${occ}/bin/nextcloud-occ onlyoffice:documentserver --check || true
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── AList 外部存储自动挂载 ──────────────────────────────────
    systemd.services.nextcloud-config-alist = {
      wantedBy = [ "multi-user.target" ];
      after = [
        "nextcloud-setup.service"
        "alist.service"
      ];
      wants = [
        "alist.service"
      ];
      script = ''
        # 确保启用 files_external 应用
        ${occ}/bin/nextcloud-occ app:enable files_external || true

        pw="$(cat ${config.sops.secrets."password".path})"
        if ! ${occ}/bin/nextcloud-occ files_external:list 2>/dev/null | grep -Fq "AList"; then
          ${occ}/bin/nextcloud-occ files_external:create AList dav password::password \
            -c host="127.0.0.1:${toString config.ports.alist}" \
            -c root="/dav/" \
            -c secure=false \
            -c user="dav" \
            -c password="$pw" || true
        else
          mount_id="$(${occ}/bin/nextcloud-occ files_external:list --output=json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | select(.mount_point == "/AList") | .mount_id' || true)"
          if [ -n "$mount_id" ]; then
            ${occ}/bin/nextcloud-occ files_external:config "$mount_id" password "$pw" || true
            ${occ}/bin/nextcloud-occ files_external:config "$mount_id" user "dav" || true
          fi
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── Preview Generator 定时批量生成缩略图 ────────────────────
    systemd.services.nextcloud-preview-generator = {
      description = "Nextcloud preview generator (batch)";
      after = [ "nextcloud-setup.service" ];
      requires = [ "nextcloud-setup.service" ];
      script = ''
        ${occ}/bin/nextcloud-occ preview:generate-all --batch-size=100
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 15;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.nextcloud-preview-generator = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # ── ClamAV 防病毒 ────────────────────────────────────────────
    services.clamav = {
      daemon.enable = true;
      daemon.settings = {
        DatabaseDirectory = "/var/lib/clamav";
        LocalSocket = "/run/clamav/clamd.ctl";
        LocalSocketMode = "666";
        User = "clamav";
        MaxFileSize = "1000M";
        MaxScanSize = "2000M";
        MaxRecursion = 20;
      };
      updater = {
        enable = true;
        frequency = 1;
      };
    };

    users.users.nextcloud.extraGroups = [ "clamav" ];

    # ── Traefik 反向代理 ─────────────────────────────────────────
    services.traefik.proxies = {
      nextcloud = {
        rule = "Host(`cloud.${domain}`)";
        target = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}";
        middlewares = [ "nextcloud-headers" ];
      };
      nextcloud-push = {
        rule = "Host(`cloud.${domain}`) && PathPrefix(`/push/`)";
        target = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}";
        middlewares = [ "nextcloud-headers" ];
      };
    };

    services.traefik.dynamicConfigOptions.http.middlewares."nextcloud-headers" = {
      headers.customRequestHeaders.Host = hostName;
    };
  };
}
