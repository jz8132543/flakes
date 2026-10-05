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

      # 1. 验证服务端连通性
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

  # 3. Zotero 全局首选项（通过 SOPS 模板动态注入 API Key 与 WebDAV 密码，每次启动自动生效）
  sops.templates."zotero-user-prefs" = {
    content = ''
      // ── 界面语言：纯正简体中文 ──
      user_pref("intl.locale.requested", "zh-CN");
      user_pref("extensions.zotero.locale", "zh-CN");
      user_pref("general.useragent.locale", "zh-CN");

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

      // ── 核心端点重定向：直连自建 Altero 数据同步服务（末尾斜杠严格保留）──
      user_pref("extensions.zotero.api.url", "https://zotero.${domain}/");
      user_pref("extensions.zotero.streaming.url", "wss://zotero.${domain}/stream");

      // ── 附件物理单副本：关闭 Zotero 内置冗余上传，全量交由 ~/Storage/Papers 按需流式挂载 ──
      user_pref("extensions.zotero.sync.storage.enabled", false);
      user_pref("extensions.zotero.sync.auto", true);

      // ── 插件自动化配置（免弹窗信任与自启动）──
      user_pref("extensions.autoDisableScopes", 0);
      user_pref("extensions.enabledScopes", 15);

      // ── Better BibTeX 自动化首选项 ──
      user_pref("extensions.zotero.translators.better-bibtex.citekeyFormat", "[auth:lower][year][veryshorttitle:lower]");
      user_pref("extensions.zotero.translators.better-bibtex.autoPinDelay", 2);
      user_pref("extensions.zotero.translators.better-bibtex.exportBibTeXStrings", "detect");

      // ── Zotero GPT 官方原生字段：完整自动写入公网 URL、API Key 与默认模型 ──
      user_pref("extensions.zotero.zoterogpt.api", "https://cpa.${domain}/v1/chat/completions");
      user_pref("extensions.zotero.zoterogpt.secretKey", "${config.sops.placeholder."cpa/api_key"}");
      user_pref("extensions.zotero.zoterogpt.model", "gpt-4o");
      user_pref("extensions.zotero.zoterogpt.api.protocol", "openai-chat");
      user_pref("extensions.zotero.zoterogpt.prompt.system", "You are a large language model serving Zotero plugin called Awesome GPT. You can directly output markdown language. Output language is Simplified Chinese.");
    '';
    path = "${profileDir}/user.js";
  };

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

  home.activation.initZoteroProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${profileDir}/extensions"
    ${pkgs.coreutils}/bin/mkdir -p "${zoteroDataDir}"
  '';
}
