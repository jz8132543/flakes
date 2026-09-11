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

  matrixRtcHosts = config.services.matrix.rtcHosts or config.lib.self.data.matrix.rtcHosts;
  talkHostName = "talk.${domain}";
in
{
  imports = [
    (import nixosModules.services.office { })
  ];

  services.nextcloud-spreed-signaling = {
    enable = true;
    hostName = talkHostName;
    backends.nextcloud = {
      urls = [ "https://${hostName}" ];
      secretFile = config.sops.templates."nextcloud-talk-hpb-backend-secret".path;
    };
    settings = {
      clients.internalsecretFile = config.sops.templates."nextcloud-talk-hpb-internal-secret".path;
      sessions = {
        hashkeyFile = "/run/nextcloud-spreed-signaling/hashkey";
        blockkeyFile = "/run/nextcloud-spreed-signaling/blockkey";
      };
      http.listen = "127.0.0.1:${toString config.ports.nextcloud-talk-hpb}";
    };
  };

  systemd.services.nextcloud-spreed-signaling-keyfiles = {
    before = [ "nextcloud-spreed-signaling.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      install -d -m 0755 -o nextcloud-spreed-signaling -g nextcloud-spreed-signaling /run/nextcloud-spreed-signaling
      head -c 32 ${
        config.sops.templates."nextcloud-talk-hpb-hashkey".path
      } > /run/nextcloud-spreed-signaling/hashkey
      head -c 32 ${
        config.sops.templates."nextcloud-talk-hpb-blockkey".path
      } > /run/nextcloud-spreed-signaling/blockkey
      chown nextcloud-spreed-signaling:nextcloud-spreed-signaling /run/nextcloud-spreed-signaling/hashkey /run/nextcloud-spreed-signaling/blockkey
      chmod 0400 /run/nextcloud-spreed-signaling/hashkey /run/nextcloud-spreed-signaling/blockkey
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  systemd.services.nextcloud-spreed-signaling = {
    after = [ "nextcloud-spreed-signaling-keyfiles.service" ];
    requires = [ "nextcloud-spreed-signaling-keyfiles.service" ];
  };

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
      dbhost = PG;
      adminuser = "i";
      adminpassFile = config.sops.secrets."password".path;
    };

    settings = {
      "overwrite.cli.url" = "https://${hostName}/";
      "upgrade.disable-web" = true;
      allow_local_remote_servers = true;
      maintenance_window_start = 2;
      default_phone_region = "CN";
      eurooffice = {
        DocumentServerUrl = "https://office.${domain}/";
        DocumentServerInternalUrl = "http://127.0.0.1:${toString config.ports.office}/";
        StorageUrl = "https://${hostName}/";
      };

      # ── 邮件配置 ──
      mail_smtpmode = "smtp";
      mail_smtphost = "${config.environment.smtp_host}";
      mail_from_address = "services";
      mail_domain = "${domain}";
      mail_smtpauth = true;
      mail_smtpname = "services@${domain}";

      # ── 缩略图预览提供商 ──────────────────────────────────────
      # https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html#enabledpreviewproviders
      enabledPreviewProviders = [
        # 默认启用的提供商
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"
        # 额外启用
        "OC\\Preview\\Image"
        "OC\\Preview\\HEIC"
        "OC\\Preview\\TIFF"
        "OC\\Preview\\Movie"
        "OC\\Preview\\MKV"
        "OC\\Preview\\MP4"
        "OC\\Preview\\AVI"
        "OC\\Preview\\PDF"
        "OC\\Preview\\SVG"
        "OC\\Preview\\Photoshop"
        "OC\\Preview\\WEBP"
      ];

      # ── Memories 应用（相册）VA-API 视频转码 ──
      "memories.vod.disable" = false;
      "memories.vod.vaapi" = true;

      # ── OIDC 登录（Keycloak）──────────────────────────────────
      lost_password_link = "disabled";
      oidc_login_provider_url = "https://sso.${domain}/realms/users";
      oidc_login_client_id = "nextcloud";
      oidc_login_auto_redirect = false;
      oidc_login_end_session_redirect = false;
      oidc_login_button_text = "Log in with KeyCloak";
      oidc_login_hide_password_form = true;
      oidc_login_use_id_token = true;
      oidc_login_attributes = {
        id = "preferred_username";
        name = "name";
        mail = "email";
        groups = "groups";
      };
      oidc_login_default_group = "oidc";
      oidc_login_use_external_storage = false;
      oidc_login_scope = "openid profile email";
      oidc_login_disable_registration = false;

      # ── ClamAV 防病毒 ────────────────────────────────────────
      # 通过 files_antivirus 应用连接本地 clamd socket
      "files_antivirus.mode" = "socket";
      "files_antivirus.socket" = "/run/clamav/clamd.ctl";

      # ── 后台任务使用 cron（性能最佳）──
      "backgroundjobs_mode" = "cron";
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "opcache.revalidate_freq" = "5";
      "opcache.jit" = "1255";
      "opcache.jit_buffer_size" = "128M";
    };

    secretFile = config.sops.templates."nextcloud-secret-config".path;

    # ── 推送通知（notify_push），不是 Talk HPB ────────────────
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
        eurooffice = pkgs.fetchNextcloudApp {
          appName = "eurooffice";
          appVersion = "11.0.0";
          url = "https://github.com/nextcloud-releases/eurooffice/releases/download/v11.0.0/eurooffice-v11.0.0.tar.gz";
          sha256 = "06pxys91nsvcp57a8i9xyyg5z1zl96anr394bmhchlapsnpgkjsn";
          license = "agpl3Plus";
        };
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

  # ── 确保 i 用户属于管理员组 ────────────────────────────────
  systemd.services.nextcloud-config-admin = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];
    script = ''
      ${occ}/bin/nextcloud-occ group:adduser admin i || true
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  systemd.services.nextcloud-config-talk-hpb = {
    wantedBy = [ "multi-user.target" ];
    after = [
      "nextcloud-setup.service"
      "nextcloud-spreed-signaling.service"
    ];
    requires = [
      "nextcloud-setup.service"
      "nextcloud-spreed-signaling.service"
    ];
    script = ''
      signaling_url="wss://${talkHostName}"
      signaling_secret="$(cat ${config.sops.templates."nextcloud-talk-hpb-backend-secret".path})"
      if ! ${occ}/bin/nextcloud-occ talk:signaling:list --output=json 2>/dev/null | grep -Fq "$signaling_url"; then
        ${occ}/bin/nextcloud-occ talk:signaling:add "$signaling_url" "$signaling_secret" --verify
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  # ── Euro-Office 自动配置与连接检测 ───────────────────────────
  systemd.services.nextcloud-config-eurooffice = {
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
      ${occ}/bin/nextcloud-occ config:app:set eurooffice DocumentServerUrl --value "https://office.${domain}/"
      ${occ}/bin/nextcloud-occ config:app:set eurooffice DocumentServerInternalUrl --value "http://127.0.0.1:${toString config.ports.office}/"
      ${occ}/bin/nextcloud-occ config:app:set eurooffice StorageUrl --value "https://${hostName}/"
      ${occ}/bin/nextcloud-occ config:app:set eurooffice jwt_secret --value "$secret"
      ${occ}/bin/nextcloud-occ config:app:set eurooffice defFormats --value '{"csv":true,"doc":true,"docm":true,"docx":true,"dot":true,"dotm":true,"dotx":true,"epub":true,"fb2":true,"fodp":true,"fods":true,"fodt":true,"htm":true,"html":true,"odp":true,"ods":true,"odt":true,"ott":true,"pot":true,"potm":true,"potx":true,"pps":true,"ppsm":true,"ppsx":true,"ppt":true,"pptm":true,"pptx":true,"rtf":true,"vsdx":true,"vsdm":true,"vssm":true,"vssx":true,"vstm":true,"vstx":true,"wps":true,"wpt":true,"xls":true,"xlsb":true,"xlsm":true,"xlsx":true,"xlt":true,"xltm":true,"xltx":true}'
      ${occ}/bin/nextcloud-occ config:app:set eurooffice editFormats --value '{"csv":true,"doc":true,"docm":true,"docx":true,"dotm":true,"dotx":true,"odp":true,"ods":true,"odt":true,"potm":true,"potx":true,"ppsm":true,"ppsx":true,"ppt":true,"pptm":true,"pptx":true,"rtf":true,"txt":true,"xls":true,"xlsb":true,"xlsm":true,"xlsx":true,"xltm":true,"xltx":true}'
      ${occ}/bin/nextcloud-occ eurooffice:documentserver --check || true
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # ── Talk TURN 服务器配置（occ）——直接复用 Matrix matrixRtcHosts 节点的 Coturn ──
  # 读取 Matrix 配置中的 matrixRtcHosts（如 nue0, sjc0 等），为 Talk 注册对应的 TURN/TURNS 节点
  systemd.services.nextcloud-config-talk = {
    wantedBy = [ "multi-user.target" ];
    after = [
      "nextcloud-setup.service"
      "coturn.service"
    ];
    requires = [ "nextcloud-setup.service" ];
    script = ''
      set -eu
      TURN_SECRET="$(cat ${config.sops.secrets."matrix/turn_shared_secret".path})"

      # ── 清理旧的 TURN 服务器 ──
      ${occ}/bin/nextcloud-occ talk:turn:list --output=json \
        | ${pkgs.jq}/bin/jq -r '.[] | .server' \
        | while read -r srv; do
            ${occ}/bin/nextcloud-occ talk:turn:delete turn "$srv" udp,tcp || true
            ${occ}/bin/nextcloud-occ talk:turn:delete turns "$srv" udp,tcp || true
            ${occ}/bin/nextcloud-occ talk:turn:delete turn,turns "$srv" udp,tcp || true
          done

      # ── 添加 Matrix 各节点的 TURN 服务器 ──
      ${lib.concatMapStringsSep "\n" (host: ''
        ${occ}/bin/nextcloud-occ talk:turn:add \
          turn,turns \
          "${host}.${domain}:5349" \
          udp,tcp \
          --secret="$TURN_SECRET"
      '') matrixRtcHosts}
    '';
    serviceConfig = {
      Type = "oneshot";
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
      frequency = 1; # 每天更新一次病毒库
    };
  };

  # 确保 nextcloud 进程可以读写 clamd socket
  users.users.nextcloud.extraGroups = [ "clamav" ];

  # ── Secrets ──────────────────────────────────────────────────
  sops.templates."nextcloud-secret-config" = {
    content = builtins.toJSON {
      mail_smtppassword = config.sops.placeholder."mail/services";
      oidc_login_client_secret = config.sops.placeholder."nextcloud/oidc-secret";
      eurooffice = {
        jwt_secret = config.sops.placeholder."onlyoffice/jwtSecretFile";
      };
    };
    owner = "nextcloud";
  };

  sops.templates."nextcloud-talk-hpb-backend-secret" = {
    content = config.sops.placeholder."nextcloud/turn-secret";
    owner = "nextcloud-spreed-signaling";
    mode = "0400";
  };

  sops.templates."nextcloud-talk-hpb-internal-secret" = {
    content = config.sops.placeholder."nextcloud/oidc-secret";
    owner = "nextcloud-spreed-signaling";
    mode = "0400";
  };

  sops.templates."nextcloud-talk-hpb-hashkey" = {
    content = config.sops.placeholder."nextcloud/turn-secret";
    owner = "nextcloud-spreed-signaling";
    mode = "0400";
  };

  sops.templates."nextcloud-talk-hpb-blockkey" = {
    content = config.sops.placeholder."nextcloud/turn-secret";
    owner = "nextcloud-spreed-signaling";
    mode = "0400";
  };

  sops.secrets."password" = {
    restartUnits = [ "nextcloud-setup.service" ];
    mode = "0444";
  };

  sops.secrets."nextcloud/oidc-secret" = {
    restartUnits = [ "nextcloud-setup.service" ];
  };

  sops.secrets."nextcloud/turn-secret" = {
    restartUnits = [ "nextcloud-spreed-signaling.service" ];
  };

  sops.secrets."mail/services" = {
    restartUnits = [ "nextcloud-setup.service" ];
  };

  sops.secrets."onlyoffice/jwtSecretFile" = {
    restartUnits = [ "nextcloud-config-eurooffice.service" ];
  };

  # matrix/turn_shared_secret 由 stun.nix（Matrix）统一管理，此处无需重复声明

  # ── Traefik 反向代理 ─────────────────────────────────────────
  services.traefik.proxies = {
    # Nextcloud 主入口
    nextcloud = {
      rule = "Host(`cloud.${domain}`)";
      target = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}";
      middlewares = [ "nextcloud-headers" ];
    };
    # notify_push 推送端点 — 必须在 /push/ 路径下，优先级更高
    nextcloud-push = {
      rule = "Host(`cloud.${domain}`) && PathPrefix(`/push/`)";
      target = "http://localhost:${toString config.ports.nextcloud-notify-push}";
      priority = 10;
    };
    nextcloud-talk-hpb = {
      rule = "Host(`${talkHostName}`)";
      target = "http://localhost:${toString config.ports.nextcloud-talk-hpb}";
    };
  };

  # Nextcloud 需要特殊 Host header（Traefik 转发时 Host 可能丢失）
  services.traefik.dynamicConfigOptions.http.middlewares."nextcloud-headers" = {
    headers.customRequestHeaders.Host = hostName;
  };
}
