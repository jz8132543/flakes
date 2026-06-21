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
in
{
  sops.secrets = {
    # "obsidian-livesync/passphrase" = { };
    # "obsidian-livesync/couchdb-user" = { };
    # "obsidian-livesync/couchdb-password" = { };
    "password" = { };
  };

  sops.templates."obsidian-livesync-settings" = {
    content = builtins.toJSON {
      couchDB_URI = "https://${syncHost}";
      # couchDB_USER = config.sops.placeholder."obsidian-livesync/couchdb-user";
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

  # home.file."${vaultRoot}/.livesync/settings.json".source =
  #   config.sops.templates."obsidian-livesync-settings".path;

  home.activation.initObsidianVault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/${vaultRoot}/.obsidian" "$HOME/${vaultRoot}/.livesync"
  '';

  home.file."${vaultRoot}/.obsidian/community-plugins.json".text = builtins.toJSON [
    "obsidian-livesync"
  ];

  home.file."${vaultRoot}/.obsidian/app.json".text = builtins.toJSON {
    livePreview = true;
    language = "zh";
  };

  home.file."${vaultRoot}/.obsidian/appearance.json".text = builtins.toJSON {
    theme = "system";
    baseFontSize = 16;
  };

  home.file."${vaultRoot}/.obsidian/core-plugins.json".text = builtins.toJSON [
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

  home.global-persistence.directories = [
    "${vaultRoot}/.obsidian"
    "${vaultRoot}/.livesync"
  ];
}
