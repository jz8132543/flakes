{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.fluxdown;
  downloadDir = "${config.xdg.userDirs.download}/FluxDown";
  chromiumId = "meleenglfggcmcajknpeeeiobnpfmahc";
  firefoxId = "fluxdown@fluxdown.app";
  mimeTypes = [
    "application/x-bittorrent"
    "x-scheme-handler/magnet"
    "x-scheme-handler/fluxdown"
    "x-scheme-handler/ed2k"
  ];
  associations = lib.genAttrs mimeTypes (_: [ "com.fluxdown.app.desktop" ]);
  relay = "${config.xdg.dataHome}/fluxdown/fluxdown_nmh.sh";
  manifest = {
    name = "com.fluxdown.nmh";
    description = "FluxDown Native Messaging Host";
    path = relay;
    type = "stdio";
  };
  nativeHosts = pkgs.symlinkJoin {
    name = "fluxdown-native-messaging-hosts";
    paths = [
      (pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/com.fluxdown.nmh.json" (
        builtins.toJSON (manifest // { allowed_extensions = [ firefoxId ]; })
      ))
      (pkgs.writeTextDir "etc/chromium/native-messaging-hosts/com.fluxdown.nmh.json" (
        builtins.toJSON (
          manifest
          // {
            allowed_origins = [
              "chrome-extension://${chromiumId}/"
              "chrome-extension://nglkkjbogjghekbhhcnccnpfedjbdhhd/"
            ];
          }
        )
      ))
    ];
  };
  firefoxExtension = pkgs.fetchurl {
    url = "https://github.com/zerx-lab/FluxDown/releases/download/v0.6.8/FluxDown-0.6.8-firefox.xpi";
    hash = "sha256-jnwU3b9mFohvsmVhxlPoMiBZ/6XYsleexQuljDQrzag=";
  };
  autostart = pkgs.makeDesktopItem {
    name = "fluxdown";
    desktopName = "FluxDown";
    exec = "${cfg.package}/bin/fluxdown-agent --autostart";
    icon = "com.fluxdown.app";
    terminal = false;
    categories = [ "Network" ];
  };
in
{
  options.programs.fluxdown = {
    enable = lib.mkEnableOption "FluxDown and native browser download integration";
    package = lib.mkPackageOption pkgs "fluxdown" { };
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the upstream FluxDown agent when the desktop session starts.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.sessionVariables.FLUXDOWN_SAVE_DIR = downloadDir;
    xdg.mimeApps = {
      enable = true;
      associations.added = associations;
      defaultApplications = associations;
    };
    # Match upstream's Unix launcher contract so startup does not replace the
    # declarative browser manifests as an apparently broken registration.
    xdg.dataFile."fluxdown/fluxdown_nmh.sh" = {
      executable = true;
      text = ''
        #!${pkgs.runtimeShell}
        exec '${cfg.package}/bin/fluxdown_nmh' "$@"
      '';
    };
    xdg.autostart = lib.mkIf cfg.autostart {
      enable = true;
      entries = [ "${autostart}/share/applications/fluxdown.desktop" ];
    };

    programs.firefox = lib.mkIf config.programs.firefox.enable {
      nativeMessagingHosts = [ nativeHosts ];
      policies.ExtensionSettings = {
        "${firefoxId}" = {
          installation_mode = "force_installed";
          install_url = "file://${firefoxExtension}";
        };
        "aria2-integration".installation_mode = "blocked";
      };
    };
    programs.chromium = lib.mkIf config.programs.chromium.enable {
      nativeMessagingHosts = [ nativeHosts ];
      extensions = [ chromiumId ];
    };
    home.file.".config/google-chrome/NativeMessagingHosts/com.fluxdown.nmh.json".source =
      "${nativeHosts}/etc/chromium/native-messaging-hosts/com.fluxdown.nmh.json";
    home.global-persistence.directories = [ ".local/share/fluxdown" ];
  };
}
