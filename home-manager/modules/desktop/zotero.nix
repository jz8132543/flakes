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
            DAV_URL="alist.${domain}/dav/189P/Sync"
            DAV_USER="dav"
            PROFILE_DIR="$HOME/${profileDir}"

            mkdir -p "$PROFILE_DIR"

            echo "==> [Zotero CLI] Configuring WebDAV settings..."
            echo "    Endpoint: https://$DAV_URL"
            echo "    User:     $DAV_USER"

            # 1. 写入 user.js 首选项
            cat > "$PROFILE_DIR/user.js" << EOF
      user_pref("extensions.zotero.sync.storage.enabled", true);
      user_pref("extensions.zotero.sync.storage.protocol", "webdav");
      user_pref("extensions.zotero.sync.storage.verified", true);
      user_pref("extensions.zotero.sync.storage.scheme", "https");
      user_pref("extensions.zotero.sync.storage.url", "$DAV_URL");
      user_pref("extensions.zotero.sync.storage.username", "$DAV_USER");
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
            HTTP_CODE="$(curl -s -k -o /dev/null -w "%{http_code}" -u "$DAV_USER:$PASSWORD" -X PROPFIND -H "Depth: 1" "https://$DAV_URL/zotero/")"
            if [ "$HTTP_CODE" = "207" ] || [ "$HTTP_CODE" = "200" ]; then
              echo "==> [SUCCESS] Zotero WebDAV connection verified successfully (HTTP $HTTP_CODE)!"
            else
              echo "==> [WARNING] WebDAV returned HTTP $HTTP_CODE. Please verify network or storage."
            fi

            echo "==> Configuration complete. Launching Zotero will now use AList WebDAV sync."
    '';
  };
in
{
  sops.secrets = {
    "password" = { };
  };

  # 注册 zotero-config-dav CLI 命令行工具
  home.packages = [ zoteroConfigDav ];

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

  # 2. Zotero WebDAV 同步首选项（user.js 会在 Zotero 每次启动时覆盖写入 prefs.js）
  home.file."${profileDir}/user.js".text = ''
    // 启用 WebDAV 附件同步
    user_pref("extensions.zotero.sync.storage.enabled", true);
    user_pref("extensions.zotero.sync.storage.protocol", "webdav");
    user_pref("extensions.zotero.sync.storage.verified", true);
    user_pref("extensions.zotero.sync.storage.scheme", "https");
    user_pref("extensions.zotero.sync.storage.url", "alist.${domain}/dav/189P/Sync");
    user_pref("extensions.zotero.sync.storage.username", "dav");
  '';

  # 3. Zotero WebDAV 凭据（利用 Mozilla LoginManager legacy 机制，启动时自动加载并迁入加密存储）
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

  # 4. 途径 B：内部 JavaScript 原生执行脚本模板
  # 可在 Zotero 内部菜单直接执行（Tools -> Developer -> Run JavaScript）
  sops.templates."zotero-setup-script" = {
    content = ''
      // Zotero WebDAV API 原生配置脚本
      (async () => {
        Zotero.Prefs.set('sync.storage.enabled', true);
        Zotero.Prefs.set('sync.storage.protocol', 'webdav');
        Zotero.Prefs.set('sync.storage.scheme', 'https');
        Zotero.Prefs.set('sync.storage.url', 'alist.${domain}/dav/189P/Sync');
        Zotero.Prefs.set('sync.storage.username', 'dav');

        var controller = Zotero.Sync.Runner.getStorageController('webdav');
        await controller.setPassword('${config.sops.placeholder."password"}');

        try {
          await controller.checkServer();
          Zotero.Prefs.set('sync.storage.verified', true);
          return 'SUCCESS: WebDAV verified and configured!';
        } catch (e) {
          Zotero.Prefs.set('sync.storage.verified', false);
          throw new Error('WebDAV Check Failed: ' + (e.message || e));
        }
      })();
    '';
    path = ".zotero/setup-webdav.js";
  };

  home.activation.initZoteroProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${profileDir}"
  '';
}
