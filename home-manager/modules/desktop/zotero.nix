{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  profileDir = ".zotero/zotero/default";
  domain = osConfig.networking.domain;
  # 统一 WebDAV 存储 Base URL：各组件独立划分子目录
  baseUrl = "https://alist.${domain}/dav/onedrive";
  papersDir = "${config.home.homeDirectory}/Storage/Papers";
  # 统一收拢到 ~/Storage 下：本地真实 SSD 目录，存放 SQLite 核心数据库
  zoteroDataDir = "${config.home.homeDirectory}/Storage/zotero";

  # 途径 B 封装：命令行一键配置与验证工具
  zoteroConfigDav = pkgs.writeShellApplication {
    name = "zotero-config-dav";
    runtimeInputs = with pkgs; [
      coreutils
      curl
    ];
    text = ''
            PASSWORD_FILE="${config.sops.secrets."password".path}"
            if [ ! -f "$PASSWORD_FILE" ]; then
              echo "Error: Password file not found at $PASSWORD_FILE" >&2
              exit 1
            fi
            PASSWORD="$(cat "$PASSWORD_FILE")"
            DAV_URL="${baseUrl}/zotero"
            DAV_USER="dav"
            PROFILE_DIR="$HOME/${profileDir}"

            mkdir -p "$PROFILE_DIR"

            echo "==> [Zotero CLI] Configuring WebDAV settings..."
            echo "    Endpoint: $DAV_URL"
            echo "    User:     $DAV_USER"

            # 1. 写入 user.js 首选项
            cat > "$PROFILE_DIR/user.js" << EOF
      user_pref("extensions.zotero.firstRun", false);
      user_pref("extensions.zotero.firstRunGuidance", false);
      user_pref("extensions.zotero.firstRun.showTour", false);
      user_pref("extensions.zotero.tour.completed", true);
      user_pref("extensions.zotero.sync.storage.enabled", true);
      user_pref("extensions.zotero.sync.storage.protocol", "webdav");
      user_pref("extensions.zotero.sync.storage.verified", true);
      user_pref("extensions.zotero.sync.storage.scheme", "https");
      user_pref("extensions.zotero.sync.storage.url", "$DAV_URL");
      user_pref("extensions.zotero.sync.storage.username", "$DAV_USER");
      user_pref("extensions.zotero.baseAttachmentPath", "${papersDir}");
      user_pref("extensions.zotero.useDataDir", true);
      user_pref("extensions.zotero.dataDir", "${zoteroDataDir}");
      EOF

            # 2. 写入登录凭据 logins.json
            cat > "$PROFILE_DIR/logins.json" << EOF
      {
        "nextId": 2,
        "logins": [
          {
            "id": 1,
            "hostname": "chrome://zotero",
            "httpRealm": "Zotero Storage Server",
            "formSubmitURL": null,
            "usernameField": "",
            "passwordField": "",
            "encryptedUsername": "",
            "encryptedPassword": "",
            "guid": "{b20c9103-a717-428e-b880-0f8724ae11ad}",
            "encType": 0,
            "timeCreated": 1726000000000,
            "timeLastUsed": 1726000000000,
            "timePasswordChanged": 1726000000000,
            "timesUsed": 1,
            "username": "$DAV_USER",
            "password": "$PASSWORD"
          }
        ],
        "potentiallyVulnerablePasswords": [],
        "dismissedBreachAlerts": []
      }
      EOF
            chmod 600 "$PROFILE_DIR/logins.json" "$PROFILE_DIR/user.js"

            # 3. 验证服务端连通性
            echo "==> [Zotero CLI] Verifying WebDAV connection with AList..."
            HTTP_CODE="$(curl -s -k -o /dev/null -w "%{http_code}" -u "$DAV_USER:$PASSWORD" -X PROPFIND -H "Depth: 1" "$DAV_URL/")"
            if [ "$HTTP_CODE" = "207" ] || [ "$HTTP_CODE" = "200" ]; then
              echo "==> [SUCCESS] Zotero WebDAV connection verified successfully (HTTP $HTTP_CODE)!"
            else
              echo "==> [WARNING] WebDAV returned HTTP $HTTP_CODE. Please verify network or storage."
            fi

            echo "==> Configuration complete."
    '';
  };
in
{
  sops.secrets = {
    "password" = { };
    "cpa/api_key" = { };
  };

  # 注册通用 zotero 桌面端（不固定版本号，统一引用 pkgs.zotero）与扩展管理
  home.packages = [
    pkgs.zotero
    zoteroConfigDav
  ];

  # 1. Zotero Profile 指向默认 profile
  home.file.".zotero/zotero/profiles.ini".text = ''
    [General]
    StartWithLastProfile=1
    Version=2

    [Profile0]
    Name=default
    IsRelative=1
    Path=default
    Default=1
  '';

  # 2. 声明式注入 Zotero 插件至 profile extensions 目录（零手动点击安装，开箱即用）
  home.file = {
    "${profileDir}/extensions/better-bibtex@iris-advies.com.xpi".source =
      "${pkgs.zoteroPlugins.better-bibtex}/zotero-better-bibtex.xpi";
    "${profileDir}/extensions/zoterogpt@polygon.org.xpi".source =
      "${pkgs.zoteroPlugins.zotero-gpt}/zotero-gpt.xpi";
  };

  # 3. Zotero 全局首选项（user.js 会在 Zotero 每次启动时自动生效）
  home.file."${profileDir}/user.js".text = ''
    // ── 彻底关闭 Zotero 首次启动新手向导、快速设置、导览与所有弹窗 ──
    user_pref("extensions.zotero.firstRun", false);
    user_pref("extensions.zotero.firstRunGuidance", false);
    user_pref("extensions.zotero.firstRun.showTour", false);
    user_pref("extensions.zotero.tour.completed", true);
    user_pref("extensions.zotero.whatsNew.showOnUpdate", false);
    user_pref("browser.rights.3.shown", true);
    user_pref("browser.tabs.warnOnClose", false);
    user_pref("toolkit.telemetry.prompted", 2);
    user_pref("toolkit.telemetry.rejected", true);

    // ── 数据目录指向 ~/Storage/zotero（本地 SSD 目录，支持毫秒级全文检索）──
    user_pref("extensions.zotero.useDataDir", true);
    user_pref("extensions.zotero.dataDir", "${zoteroDataDir}");

    // ── 核心设计：链接附件基准目录（论文在物理上只在挂载目录 ${papersDir} 存一份纯 PDF）──
    user_pref("extensions.zotero.baseAttachmentPath", "${papersDir}");

    // ── 自动启用并连接 WebDAV 存储（已验证通过，免手动进设置验证）──
    user_pref("extensions.zotero.sync.storage.enabled", true);
    user_pref("extensions.zotero.sync.storage.protocol", "webdav");
    user_pref("extensions.zotero.sync.storage.verified", true);
    user_pref("extensions.zotero.sync.storage.scheme", "https");
    user_pref("extensions.zotero.sync.storage.url", "${baseUrl}/zotero");
    user_pref("extensions.zotero.sync.storage.username", "dav");
    user_pref("extensions.zotero.sync.auto", true);

    // ── 插件自动化配置（免弹窗信任与自启动）──
    user_pref("extensions.autoDisableScopes", 0);
    user_pref("extensions.enabledScopes", 15);

    // ── Better BibTeX 自动化首选项 ──
    user_pref("extensions.zotero.translators.better-bibtex.citekeyFormat", "[auth:lower][year][veryshorttitle:lower]");
    user_pref("extensions.zotero.translators.better-bibtex.autoPinDelay", 2);
    user_pref("extensions.zotero.translators.better-bibtex.exportBibTeXStrings", "detect");

    // ── CPA (AI Proxy) 接入首选项：支持第三方中转站（自定义公网 URL 与 APIKey）──
    user_pref("extensions.zotero.ai.endpoint", "https://cpa.${domain}/v1");
    user_pref("extensions.zotero.ai.customModel", "gpt-4o");
    user_pref("extensions.zotero.translate.ai.serverUrl", "https://cpa.${domain}/v1");
  '';

  # 4. Zotero WebDAV 凭据（自动写入 Mozilla logins.json）
  sops.templates."zotero-logins" = {
    content = builtins.toJSON {
      nextId = 2;
      logins = [
        {
          id = 1;
          hostname = "chrome://zotero";
          httpRealm = "Zotero Storage Server";
          formSubmitURL = null;
          usernameField = "";
          passwordField = "";
          encryptedUsername = "";
          encryptedPassword = "";
          guid = "{b20c9103-a717-428e-b880-0f8724ae11ad}";
          encType = 0;
          timeCreated = 1726000000000;
          timeLastUsed = 1726000000000;
          timePasswordChanged = 1726000000000;
          timesUsed = 1;
          username = "dav";
          password = config.sops.placeholder."password";
        }
      ];
      potentiallyVulnerablePasswords = [ ];
      dismissedBreachAlerts = [ ];
    };
    path = "${profileDir}/logins.json";
  };

  # 5. Zotero AI 插件配置文件（自动注入公网自定义 URL 与 API Key，全面兼容中转站）
  sops.templates."zotero-ai-config" = {
    content = builtins.toJSON {
      apiProvider = "openai-compatible";
      apiBaseUrl = "https://cpa.${domain}/v1";
      apiKey = config.sops.placeholder."cpa/api_key";
      model = "gpt-4o";
      enableCustomProxy = true;
    };
    path = "${profileDir}/ai-settings.json";
  };

  home.activation.initZoteroProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${profileDir}/extensions"
    ${pkgs.coreutils}/bin/mkdir -p "${zoteroDataDir}"
  '';
}
