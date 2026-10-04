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
  # 统一 WebDAV 存储 Base URL：Zotero 仅作为备用同步路径
  storageBaseUrl = "https://alist.${domain}/dav/onedrive";
  papersDir = "${config.home.homeDirectory}/Storage/Papers";

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
            DAV_URL="${storageBaseUrl}/zotero"
            DAV_USER="dav"
            PROFILE_DIR="$HOME/${profileDir}"

            mkdir -p "$PROFILE_DIR"

            echo "==> [Zotero CLI] Configuring WebDAV settings..."
            echo "    Endpoint: $DAV_URL"
            echo "    User:     $DAV_USER"

            # 1. 写入 user.js 首选项
            cat > "$PROFILE_DIR/user.js" << EOF
      user_pref("extensions.zotero.sync.storage.enabled", false);
      user_pref("extensions.zotero.sync.storage.protocol", "webdav");
      user_pref("extensions.zotero.sync.storage.verified", true);
      user_pref("extensions.zotero.sync.storage.scheme", "https");
      user_pref("extensions.zotero.sync.storage.url", "$DAV_URL");
      user_pref("extensions.zotero.sync.storage.username", "$DAV_USER");
      user_pref("extensions.zotero.baseAttachmentPath", "${papersDir}");
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

  # 注册通用 zotero 桌面端（不锁版本，跟踪系统最新构建）与命令行工具
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

  # 2. Zotero 全局首选项（user.js 会在 Zotero 每次启动时自动生效）
  home.file."${profileDir}/user.js".text = ''
    // ── 核心设计：关闭官方 WebDAV zip 附件打包，彻底避免云端双份存储 ──
    user_pref("extensions.zotero.sync.storage.enabled", false);

    // ── 核心设计：链接附件基准目录（Linked Attachment Base Directory）──
    // 论文在物理上只在挂载目录 ${papersDir} 中存放单份 PDF，Zotero 仅持有相对路径链接
    user_pref("extensions.zotero.baseAttachmentPath", "${papersDir}");
    user_pref("extensions.zotero.useDataDir", false);

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

  # 3. Zotero WebDAV 凭据（自动写入 Mozilla logins.json）
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

  # 4. Zotero AI 插件配置文件（若安装 zotero-gpt / translate 类插件，自动注入公网自定义 URL 与 API Key）
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
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${profileDir}"
  '';
}
