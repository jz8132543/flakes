{
  config,
  osConfig,
  ...
}:
let
  vaultRoot = "Sync";
  syncHost = "sync.${osConfig.networking.domain}";
in
{
  sops.secrets = {
    "password" = { };
  };

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
  };

  home.file."${vaultRoot}/.livesync/settings.json".source =
    config.sops.templates."obsidian-livesync-settings".path;

  home.file."${vaultRoot}/.obsidian/community-plugins.json".text = builtins.toJSON [
    "obsidian-livesync"
  ];

  home.file."${vaultRoot}/.obsidian/app.json".text = builtins.toJSON {
    livePreview = true;
  };

  home.global-persistence.directories = [
    "${vaultRoot}/.obsidian"
    "${vaultRoot}/.livesync"
  ];
}
