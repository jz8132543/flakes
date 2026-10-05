{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  # 统一收拢到 ~/Storage 下：本地真实 SSD 目录，由 LiveSync 负责双向同步
  vaultRoot = "Storage/obsidian";
  domain = osConfig.networking.domain;
  baseUrl = "https://alist.${domain}/dav/onedrive";
  papersDir = "${config.home.homeDirectory}/Storage/Papers";
  couchHost = "couchdb.${domain}";

  # 自动化联调验证工具：一键测试 CouchDB、WebDAV 与 CPA AI
  obsidianCheck = pkgs.writeShellApplication {
    name = "obsidian-couchdb-check";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = ''
      PASSWORD_FILE="${config.sops.secrets."password".path}"
      if [ ! -f "$PASSWORD_FILE" ]; then
        echo "[ERROR] Password file not found at $PASSWORD_FILE" >&2
        exit 1
      fi
      PASSWORD="$(cat "$PASSWORD_FILE")"

      echo "========================================================"
      echo "  Obsidian & Academic Stack Automated Connectivity Test"
      echo "========================================================"

      # 1. 测试 CouchDB 连通性与认证
      echo "--> [1/3] Testing CouchDB (${couchHost})..."
      COUCH_RESP="$(curl -s -u "obsidian:$PASSWORD" "https://${couchHost}/" || true)"
      if echo "$COUCH_RESP" | jq -e '.couchdb' >/dev/null 2>&1; then
        VERSION="$(echo "$COUCH_RESP" | jq -r '.version')"
        echo "    [OK] CouchDB online! Version: $VERSION"
      else
        echo "    [FAILED] CouchDB response invalid: $COUCH_RESP"
      fi

      DB_RESP="$(curl -s -u "obsidian:$PASSWORD" "https://${couchHost}/_all_dbs" || true)"
      if echo "$DB_RESP" | grep -q "obsidiannotes"; then
        echo "    [OK] Database 'obsidiannotes' exists and accessible!"
      else
        echo "    [WARNING] Database 'obsidiannotes' not detected: $DB_RESP"
      fi

      # 2. 测试 AList WebDAV 存储
      echo "--> [2/3] Testing AList WebDAV (${baseUrl})..."
      HTTP_CODE="$(curl -s -k -o /dev/null -w "%{http_code}" -u "dav:$PASSWORD" -X PROPFIND -H "Depth: 1" "${baseUrl}/" || true)"
      if [ "$HTTP_CODE" = "207" ] || [ "$HTTP_CODE" = "200" ]; then
        echo "    [OK] WebDAV connection verified successfully (HTTP $HTTP_CODE)!"
      else
        echo "    [WARNING] WebDAV returned HTTP $HTTP_CODE"
      fi

      # 3. 测试 CPA AI 接口服务
      echo "--> [3/3] Testing CPA AI Gateway (https://cpa.${domain}/v1)..."
      CPA_KEY_FILE="${config.sops.secrets."cpa/api_key".path}"
      CPA_KEY=""
      if [ -f "$CPA_KEY_FILE" ]; then
        CPA_KEY="$(cat "$CPA_KEY_FILE")"
      else
        CPA_KEY="$PASSWORD"
      fi
      CPA_CODE="$(curl -s -k -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $CPA_KEY" "https://cpa.${domain}/v1/models" || true)"
      if [ "$CPA_CODE" = "200" ]; then
        echo "    [OK] CPA API Gateway accessible and authorized (HTTP $CPA_CODE)!"
      else
        echo "    [WARNING] CPA API returned HTTP $CPA_CODE"
      fi

      echo "========================================================"
      echo "  All service connectivity checks finished."
      echo "========================================================"
    '';
  };
  obsidianPkg = pkgs.obsidian.override {
    commandLineArgs = "--lang=zh-CN";
  };
in
{
  sops.secrets = {
    "password" = { };
    "cpa/api_key" = { };
  };

  # 声明式安装通用 Obsidian（预注入中文环境）与测试工具
  home.packages = [
    obsidianPkg
    obsidianCheck
  ];

  # ── 1. 彻底跳过新手配置向导：预置全局 obsidian.json 与默认 Vault ───────
  # 当首次打开 Obsidian 时，检测到已有处于 open: true 状态的 Vault，
  # 瞬间跳过“创建新库/打开已有库”向导，直接进入主编辑界面，并锁定中文！
  home.file = {
    ".config/obsidian/obsidian.json".text = builtins.toJSON {
      vaults = {
        "storage-obsidian-vault" = {
          path = "${config.home.homeDirectory}/${vaultRoot}";
          ts = 1726000000000;
          open = true;
        };
      };
      language = "zh";
      insider = false;
    };

    "${vaultRoot}/.obsidian/community-plugins.json".text = builtins.toJSON [
      # 跨端秒级同步与学术研究插件
      "obsidian-livesync"
      "remotely-save"
      "obsidian-zotero-desktop-connector"
      "copilot"

      # Life Compass (Life OS) 模板核心插件体系
      "dataview"
      "templater-obsidian"
      "periodic-notes"
      "quickadd"
      "obsidian-tasks-plugin"
      "obsidian-kanban"
      "omnisearch"
      "obsidian-local-rest-api"
      "agent-client"
      "seo"
      "life-os-app"
    ];

    "${vaultRoot}/.obsidian/app.json".text = builtins.toJSON {
      livePreview = true;
      language = "zh";
      attachmentFolderPath = "Attachments";
    };

    # 声明式自动部署插件核心代码（0 手动点击下载，开箱即用）
    "${vaultRoot}/.obsidian/plugins/obsidian-livesync/main.js".source =
      "${pkgs.obsidianPlugins.livesync}/main.js";
    "${vaultRoot}/.obsidian/plugins/obsidian-livesync/manifest.json".source =
      "${pkgs.obsidianPlugins.livesync}/manifest.json";
    "${vaultRoot}/.obsidian/plugins/obsidian-livesync/styles.css".source =
      "${pkgs.obsidianPlugins.livesync}/styles.css";

    "${vaultRoot}/.obsidian/plugins/copilot/main.js".source = "${pkgs.obsidianPlugins.copilot}/main.js";
    "${vaultRoot}/.obsidian/plugins/copilot/manifest.json".source =
      "${pkgs.obsidianPlugins.copilot}/manifest.json";
    "${vaultRoot}/.obsidian/plugins/copilot/styles.css".source =
      "${pkgs.obsidianPlugins.copilot}/styles.css";

    "${vaultRoot}/.obsidian/plugins/remotely-save/main.js".source =
      "${pkgs.obsidianPlugins.remotely-save}/main.js";
    "${vaultRoot}/.obsidian/plugins/remotely-save/manifest.json".source =
      "${pkgs.obsidianPlugins.remotely-save}/manifest.json";
    "${vaultRoot}/.obsidian/plugins/remotely-save/styles.css".source =
      "${pkgs.obsidianPlugins.remotely-save}/styles.css";

    "${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector/main.js".source =
      "${pkgs.obsidianPlugins.zotero-integration}/main.js";
    "${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector/manifest.json".source =
      "${pkgs.obsidianPlugins.zotero-integration}/manifest.json";
    "${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector/styles.css".source =
      "${pkgs.obsidianPlugins.zotero-integration}/styles.css";
  };

  # ── 2. 核心：CouchDB 数据库自动直连配置（NoSQL 文档型数据库）─────
  # 预置 isConfigured = true 与凭据，Obsidian 启动后静默连接 CouchDB，实现免 Restic 迁移
  sops.templates."obsidian-livesync-settings" = {
    content = builtins.toJSON {
      couchDB_URI = "https://${couchHost}";
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
      usePluginSync = true;
      autoSweepPlugins = false;
      autoSweepPluginsPeriodic = false;
      isConfigured = true;
    };
    path = "${vaultRoot}/.obsidian/plugins/obsidian-livesync/data.json";
  };

  # ── 3. 备用同步：Remotely Save 指向 ${baseUrl}/obsidian ─────────
  sops.templates."obsidian-remotely-save" = {
    content = builtins.toJSON {
      syncConfigSlug = "remotely-save";
      syncServiceType = "webdav";
      webdav = {
        url = "${baseUrl}/obsidian/";
        username = "dav";
        password = config.sops.placeholder."password";
        depth = "manual";
        manualRecursive = false;
      };
      autoRun = 0; # 默认优先由 CouchDB LiveSync 接管秒级流式同步
      syncOnSave = false;
      syncOnStart = false;
      agreeToUploadLargeFiles = true;
    };
    path = "${vaultRoot}/.obsidian/plugins/remotely-save/data.json";
  };

  # ── 4. Zotero Integration 自动配置与单份论文引用模板 ───────────
  sops.templates."obsidian-zotero-integration" = {
    content = builtins.toJSON {
      version = 1;
      betterBibTexExportUrl = "http://127.0.0.1:23119/better-bibtex/export/collection";
      citationExportFormat = "better-bibtex";
      database = "zotero";
      enableLocalFileLink = true;
      importPath = "Literature";
      templates = [
        {
          name = "Academic Paper Note";
          id = "academic-paper-default";
          format = ''
            ---
            citekey: {{citekey}}
            title: "{{title}}"
            authors: [{{authors}}]
            year: {{year}}
            doi: {{doi}}
            zotero_link: zotero://select/items/@{{citekey}}
            pdf_path: "file://${papersDir}/{{citekey}}.pdf"
            tags: [literature, {{tags}}]
            ---

            # {{title}}

            - **Zotero Link**: [Open in Zotero](zotero://select/items/@{{citekey}})
            - **Physical PDF**: [Open Cloud-Backed PDF](${papersDir}/{{citekey}}.pdf)

            ## Abstract
            {{abstractNote}}

            ## Annotations & Key Highlights
            {{annotations}}
          '';
        }
      ];
    };
    path = "${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector/data.json";
  };

  # ── 5. AI Copilot 自动配置：全面支持第三方中转站（精准适配 Copilot v4 数据模型）──
  sops.templates."obsidian-copilot-settings" = {
    content = builtins.toJSON {
      openAIApiKey = config.sops.placeholder."cpa/api_key";
      openAIProxyBaseUrl = "https://cpa.${domain}/v1";
      defaultModelKey = "gpt-4o|openai";
      defaultChainType = "llm_chain";
      stream = true;
      userSystemPrompt = "你是一个专业的学术研究助手和知识合成专家，请始终使用中文进行回复。";
      activeModels = [
        {
          name = "gpt-4o";
          provider = "openai";
          enabled = true;
          isBuiltIn = true;
          capabilities = [ "vision" ];
        }
        {
          name = "claude-3-5-sonnet";
          provider = "openai";
          enabled = true;
          isBuiltIn = false;
          capabilities = [
            "vision"
            "reasoning"
          ];
        }
        {
          name = "gemini-3.8-flash";
          provider = "openai";
          enabled = true;
          isBuiltIn = false;
          capabilities = [ "vision" ];
        }
      ];
    };
    path = "${vaultRoot}/.obsidian/plugins/copilot/data.json";
  };

  # 声明式预创建各插件数据目录与 Vault 结构，并确保全局 UI 中文字符集生效
  home.activation.initObsidianDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.coreutils}/bin/mkdir -p \
          "$HOME/.config/obsidian" \
          "$HOME/${vaultRoot}/.obsidian/plugins/obsidian-livesync" \
          "$HOME/${vaultRoot}/.obsidian/plugins/remotely-save" \
          "$HOME/${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector" \
          "$HOME/${vaultRoot}/.obsidian/plugins/copilot" \
          "$HOME/${vaultRoot}/Literature" \
          "$HOME/${vaultRoot}/Attachments"

        if [ -d "$HOME/.config/obsidian/Local Storage/leveldb" ]; then
          ${pkgs.python3.withPackages (ps: [ ps.plyvel ])}/bin/python3 - <<'PYEOF' || true
    import os
    try:
        import plyvel
        path = os.path.expanduser("~/.config/obsidian/Local Storage/leveldb")
        db = plyvel.DB(path, create_if_missing=False)
        db.put(b"_app://obsidian.md\x00\x01language", b"\x01zh")
        db.close()
    except Exception:
        pass
    PYEOF
        fi
  '';

  home.global-persistence.directories = [
    "${vaultRoot}/.obsidian"
    ".config/obsidian"
  ];
}
