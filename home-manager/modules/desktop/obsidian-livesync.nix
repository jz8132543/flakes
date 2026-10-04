{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  vaultRoot = "Sync";
  domain = osConfig.networking.domain;
  # 统一 WebDAV 存储 Base URL：Obsidian 独立子目录为 ${storageBaseUrl}/obsidian
  storageBaseUrl = "https://alist.${domain}/dav/onedrive";
  papersDir = "${config.home.homeDirectory}/Storage/Papers";
  couchHost = "sync.${domain}";
in
{
  sops.secrets = {
    "password" = { };
    "cpa/api_key" = { };
  };

  # 声明式安装通用 Obsidian（跟踪 Nixpkgs 最新版）
  home.packages = with pkgs; [
    obsidian
  ];

  # ── 1. 声明式配置已启用的社区插件与核心设置 ─────────────────────
  # 当 Obsidian 打开 Vault 时，检测到 community-plugins.json 声明的插件
  # 配合已注入的配置文件即可直接加载使用
  home.file = {
    "${vaultRoot}/.obsidian/community-plugins.json".text = builtins.toJSON [
      "obsidian-livesync"
      "remotely-save"
      "obsidian-zotero-desktop-connector"
      "copilot"
    ];

    "${vaultRoot}/.obsidian/app.json".text = builtins.toJSON {
      livePreview = true;
      language = "zh";
      attachmentFolderPath = "Attachments";
    };
  };

  # ── 2. 核心：CouchDB 数据库自动直连配置（NoSQL 文档型数据库）─────
  # 替代传统文件同步，每一篇笔记的改动实时入库 CouchDB，实现免 Restic 迁移
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

  # ── 3. 备用同步：Remotely Save 指向 ${storageBaseUrl}/obsidian ──
  sops.templates."obsidian-remotely-save" = {
    content = builtins.toJSON {
      syncConfigSlug = "remotely-save";
      syncServiceType = "webdav";
      webdav = {
        url = "${storageBaseUrl}/obsidian/";
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

  # ── 5. AI Copilot 自动配置：全面支持第三方中转站（自定义公网 URL 与 APIKey）──
  sops.templates."obsidian-copilot-settings" = {
    content = builtins.toJSON {
      openAIApiKey = config.sops.placeholder."cpa/api_key";
      openAIBaseUrl = "https://cpa.${domain}/v1";
      defaultModel = "gpt-4o";
      temperature = 0.5;
      stream = true;
      systemPrompt = "You are a professional academic research assistant and knowledge synthesizer.";
      activeProvider = "openai";
      customModelApiUrl = "https://cpa.${domain}/v1";
      customModelApiKey = config.sops.placeholder."cpa/api_key";
      models = [
        {
          name = "gpt-4o";
          provider = "openai";
          baseUrl = "https://cpa.${domain}/v1";
          apiKey = config.sops.placeholder."cpa/api_key";
        }
        {
          name = "claude-3-5-sonnet-20241022";
          provider = "openai";
          baseUrl = "https://cpa.${domain}/v1";
          apiKey = config.sops.placeholder."cpa/api_key";
        }
        {
          name = "deepseek-chat";
          provider = "openai";
          baseUrl = "https://cpa.${domain}/v1";
          apiKey = config.sops.placeholder."cpa/api_key";
        }
      ];
    };
    path = "${vaultRoot}/.obsidian/plugins/copilot/data.json";
  };

  # 声明式预创建各插件数据目录与 Vault 结构
  home.activation.initObsidianDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p \
      "$HOME/${vaultRoot}/.obsidian/plugins/obsidian-livesync" \
      "$HOME/${vaultRoot}/.obsidian/plugins/remotely-save" \
      "$HOME/${vaultRoot}/.obsidian/plugins/obsidian-zotero-desktop-connector" \
      "$HOME/${vaultRoot}/.obsidian/plugins/copilot" \
      "$HOME/${vaultRoot}/Literature" \
      "$HOME/${vaultRoot}/Attachments"
  '';

  home.global-persistence.directories = [
    "${vaultRoot}/.obsidian"
  ];
}
