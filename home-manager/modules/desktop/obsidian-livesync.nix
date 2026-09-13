{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  vaultRoot = "Sync";
  syncHost = "sync.${osConfig.networking.domain}";

  # 封装 Remotely Save 插件包供 programs.obsidian.vaults.<name>.communityPlugins 使用
  remotelySavePkg = pkgs.runCommand "obsidian-remotely-save-0.5.25" { } ''
    mkdir -p $out
    cp ${
      pkgs.fetchurl {
        url = "https://github.com/remotely-save/remotely-save/releases/download/0.5.25/main.js";
        sha256 = "017s24n3d6agfxrg1g0avhsa9fk9g1h5ij8q8rwbk22iy4kvvbxk";
      }
    } $out/main.js
    cp ${
      pkgs.fetchurl {
        url = "https://github.com/remotely-save/remotely-save/releases/download/0.5.25/manifest.json";
        sha256 = "145a9inbj0195nhk7sapaxak2nvf564amrw0d1lklgq02svc1nbi";
      }
    } $out/manifest.json
    cp ${
      pkgs.fetchurl {
        url = "https://github.com/remotely-save/remotely-save/releases/download/0.5.25/styles.css";
        sha256 = "1cyzw3lr5jikrry4ny5zwz52na7a15dn5cpvg998r9ccadylwn47";
      }
    } $out/styles.css
  '';
in
{
  sops.secrets = {
    "password" = { };
  };

  # ── Home-Manager 原生 programs.obsidian 模块配置 ───────────────
  programs.obsidian = {
    enable = true;
    vaults."${vaultRoot}" = {
      target = vaultRoot;
      settings = {
        app = {
          livePreview = true;
          language = "zh";
        };
        appearance = {
          theme = "system";
          baseFontSize = 16;
        };
        corePlugins = [
          "file-explorer"
          "global-search"
          "backlink"
          "outgoing-link"
          "tag-pane"
          "page-preview"
          "properties"
          "daily-notes"
          "templates"
          "note-composer"
          "file-recovery"
          "command-palette"
          "word-count"
          "bookmarks"
          "outline"
        ];
        communityPlugins = [
          { pkg = remotelySavePkg; }
        ];
      };
    };
  };

  # ── 敏感凭据（WebDAV 密码）通过 SOPS 模板注入插件目录 ────────
  # 注意：communityPlugins.settings 会写入 /nix/store，为防止明文密码泄漏，使用 sops 模板动态写入
  sops.templates."obsidian-remotely-save" = {
    content = builtins.toJSON {
      syncConfigSlug = "remotely-save";
      syncServiceType = "webdav";
      webdav = {
        url = "https://alist.${osConfig.networking.domain}/dav/189P/Sync/Obsidian/";
        username = "dav";
        password = config.sops.placeholder."password";
        depth = "manual";
        manualRecursive = false;
      };
      autoRun = 1;
      syncOnSave = true;
      syncOnStart = true;
      initRun = true;
      agreeToUploadLargeFiles = true;
    };
    path = "${vaultRoot}/.obsidian/plugins/remotely-save/data.json";
  };

  # LiveSync CouchDB 凭据备用
  sops.templates."obsidian-livesync-settings" = {
    content = builtins.toJSON {
      couchDB_URI = "https://${syncHost}";
      couchDB_USER = "obsidian";
      couchDB_PASSWORD = config.sops.placeholder."password";
      couchDB_DBNAME = "obsidiannotes";
      liveSync = true;
      syncOnSave = true;
      syncOnStart = true;
      syncOnFileOpen = true;
      savingDelay = 200;
      periodicReplication = false;
      encrypt = true;
      passphrase = config.sops.placeholder."password";
      usePluginSync = false;
      autoSweepPlugins = false;
      autoSweepPluginsPeriodic = false;
      isConfigured = true;
    };
    path = "${vaultRoot}/.livesync/settings.json";
  };

  home.activation.initObsidianVault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${vaultRoot}/.obsidian/plugins/remotely-save" "$HOME/${vaultRoot}/.livesync"
  '';

  home.global-persistence.directories = [
    "${vaultRoot}/.obsidian"
    "${vaultRoot}/.livesync"
  ];
}
