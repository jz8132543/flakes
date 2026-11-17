{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.wineAudio;
  wine = cfg.package;
  cfxRoot = "${cfg.dataDirectory}/Garritan-CFX";
  d274Root = "${cfg.dataDirectory}/D-274";
  entryNames = [
    "garritan-cfx"
    "garritan-cfx-desktop"
    "vsl-concert-d274"
    "vsl-concert-d274-desktop"
  ];
  environment = root: [
    "${pkgs.coreutils}/bin/env"
    "WINEPREFIX=${root}/prefix"
    "XDG_CONFIG_HOME=${root}/xdg-config"
    "XDG_DATA_HOME=${root}/xdg-data"
    "XDG_CACHE_HOME=${root}/xdg-cache"
    "XDG_STATE_HOME=${root}/xdg-state"
    "TMPDIR=${root}/temp"
    "WINEDLLOVERRIDES=winemenubuilder.exe=d"
    "WINEDEBUG=-all"
  ];
  # Exec arguments need both desktop-file string and quoted-argument escaping.
  quoteDesktopArgument =
    argument:
    "\""
    + lib.replaceStrings [ "\\" "\"" "`" "$" ] [ "\\\\\\\\" "\\\\\"" "\\\\`" "\\\\$" ] argument
    + "\"";
  desktopCommand = arguments: lib.concatMapStringsSep " " quoteDesktopArgument arguments;
  setupScript = pkgs.writeText "wine-audio-desktop.vbs" (
    builtins.readFile ./scripts/setup-desktop.vbs
  );
  prepareDesktop = pkgs.writeShellScript "prepare-wine-audio-desktop" ''
    set -euo pipefail
    umask 077
    root=${lib.escapeShellArg d274Root}
    ${pkgs.coreutils}/bin/mkdir -p "$root" \
      "$root/xdg-config" "$root/xdg-data" "$root/xdg-cache" \
      "$root/xdg-state" "$root/temp"
    export WINEPREFIX="$root/prefix"
    export XDG_CONFIG_HOME="$root/xdg-config"
    export XDG_DATA_HOME="$root/xdg-data"
    export XDG_CACHE_HOME="$root/xdg-cache"
    export XDG_STATE_HOME="$root/xdg-state"
    export TMPDIR="$root/temp"
    export WINEDLLOVERRIDES=winemenubuilder.exe=d
    export WINEDEBUG=-all
    if [[ ! -f "$WINEPREFIX/drive_c/windows/syswow64/kernel32.dll" ]]; then
      WINEARCH=win64 WINEDLLOVERRIDES=winemenubuilder.exe,mscoree,mshtml=d \
        ${wine}/bin/wineboot --init
      test -f "$WINEPREFIX/drive_c/windows/syswow64/kernel32.dll"
    fi
    ${pkgs.coreutils}/bin/chmod 0700 "$WINEPREFIX"
    ${wine}/bin/wine cscript.exe //NoLogo //B \
      ${lib.escapeShellArg ("Z:" + lib.replaceStrings [ "/" ] [ "\\" ] (toString setupScript))}
    # Wine's script host can exit zero on an unhandled COM error.
    test -s "$WINEPREFIX/drive_c/AudioDesktop/My Computer.lnk"
  '';
in
{
  options.programs.wineAudio = {
    enable = lib.mkEnableOption "isolated Wine desktops and piano launchers for CFX and Vienna Synchron Pianos";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wineWow64Packages.yabridge;
      description = "The Wine runner shared by these two isolated audio prefixes.";
    };
    dataDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/games/Audio";
      description = "Absolute directory containing the separate CFX and D-274 environments.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.dataDirectory;
        message = "programs.wineAudio.dataDirectory must be an absolute path.";
      }
    ];
    xdg.desktopEntries = {
      garritan-cfx = {
        name = "Garritan CFX Concert Grand";
        genericName = "Piano";
        comment = "Open the CFX Full player directly without a Wine virtual desktop";
        icon = "audio-x-generic";
        terminal = false;
        startupNotify = false;
        categories = [
          "AudioVideo"
          "Audio"
        ];
        settings = {
          Keywords = "CFX;Garritan;Piano;Wine;";
          Path = cfxRoot;
        };
        exec = desktopCommand (
          environment cfxRoot
          ++ [
            "${wine}/bin/wine"
            "C:\\Program Files\\Garritan\\CFX Concert Grand\\CFX Concert Grand x64.exe"
          ]
        );
      };
      garritan-cfx-desktop = {
        name = "Garritan CFX - Wine Desktop";
        genericName = "Wine Desktop";
        comment = "Open the CFX environment desktop without automatically starting the piano";
        icon = "computer";
        terminal = false;
        startupNotify = false;
        categories = [
          "AudioVideo"
          "Audio"
        ];
        settings = {
          Keywords = "CFX;Garritan;Piano;Wine;Desktop;";
          Path = cfxRoot;
        };
        exec = desktopCommand (
          environment cfxRoot
          ++ [
            "${wine}/bin/wine"
            "explorer.exe"
            "/desktop=CFX,1024x768"
          ]
        );
      };
      vsl-concert-d274 = {
        name = "VSL Concert D-274";
        genericName = "Piano";
        comment = "Open Vienna Synchron Pianos directly without a Wine virtual desktop";
        icon = "audio-x-generic";
        terminal = false;
        startupNotify = false;
        categories = [
          "AudioVideo"
          "Audio"
        ];
        settings = {
          Keywords = "VSL;Concert;D-274;Piano;Wine;";
          Path = d274Root;
        };
        exec = desktopCommand (
          environment d274Root
          ++ [
            "${wine}/bin/wine"
            "C:\\Program Files\\VSL\\Vienna Synchron Pianos\\Vienna Synchron Pianos.exe"
          ]
        );
      };
      vsl-concert-d274-desktop = {
        name = "VSL Concert D-274 - Wine Desktop";
        genericName = "Wine Desktop";
        comment = "Open the D-274 environment desktop without automatically starting the piano";
        icon = "computer";
        terminal = false;
        startupNotify = false;
        categories = [
          "AudioVideo"
          "Audio"
        ];
        settings = {
          Keywords = "VSL;Concert;D-274;Piano;Wine;Desktop;";
          Path = d274Root;
        };
        exec = desktopCommand (
          environment d274Root
          ++ [
            "${wine}/bin/wine"
            "explorer.exe"
            "/desktop=D-274,1024x768"
          ]
        );
      };
    };
    # Publish the HM-generated entries in the user data directory as well.
    xdg.dataFile = lib.listToAttrs (
      map (name: {
        name = "applications/${name}.desktop";
        value.source = "${
          lib.findFirst (
            package: package.name == "${name}.desktop"
          ) (throw "Missing Home Manager desktop entry package: ${name}") config.home.packages
        }/share/applications/${name}.desktop";
      }) entryNames
    );
    home.activation.prepareWineAudioDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${prepareDesktop}
    '';
  };
}
