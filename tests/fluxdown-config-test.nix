{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  results = lib.genAttrs [ "arx8" "surface" ] (
    name:
    let
      host = configurations.${name};
      home = host.config.home-manager.users.tippy;
      fluxdown = home.programs.fluxdown;
      extensions = home.programs.firefox.policies.ExtensionSettings;
      mime = home.xdg.mimeApps.defaultApplications;
      downloadDir = "${home.xdg.userDirs.download}/FluxDown";
    in
    assert fluxdown.enable;
    assert fluxdown.autostart;
    assert home.home.sessionVariables.FLUXDOWN_SAVE_DIR == downloadDir;
    assert lib.elem fluxdown.package home.home.packages;
    assert extensions."fluxdown@fluxdown.app".installation_mode == "force_installed";
    assert lib.hasPrefix "file:///nix/store/" extensions."fluxdown@fluxdown.app".install_url;
    assert extensions."aria2-integration".installation_mode == "blocked";
    assert lib.elem "meleenglfggcmcajknpeeeiobnpfmahc" host.config.programs.chromium.extensions;
    assert !lib.elem "mpkodccbngfoacfalldjimigihfbocjn" host.config.programs.chromium.extensions;
    assert
      host.config.programs.chromium.extraOpts.ExtensionSettings."mpkodccbngfoacfalldjimigihfbocjn".installation_mode
      == "blocked";
    assert builtins.all (type: mime.${type} == [ "com.fluxdown.app.desktop" ]) [
      "application/x-bittorrent"
      "x-scheme-handler/magnet"
      "x-scheme-handler/fluxdown"
      "x-scheme-handler/ed2k"
    ];
    assert !lib.elem "com.fluxdown.app.desktop" mime."x-scheme-handler/http";
    assert !lib.elem "com.fluxdown.app.desktop" mime."x-scheme-handler/https";
    assert home.xdg.dataFile."fluxdown/fluxdown_nmh.sh".executable;
    assert lib.elem ".local/share/fluxdown" home.home.global-persistence.directories;
    {
      inherit (fluxdown) package;
      inherit downloadDir;
      firefoxManifest = home.home.file.".mozilla/native-messaging-hosts".source;
      chromiumManifest = home.home.file."${home.xdg.configHome}/chromium/NativeMessagingHosts".source;
      autostart = home.xdg.configFile.autostart.source;
      relay = home.xdg.dataFile."fluxdown/fluxdown_nmh.sh".source;
    }
  );
in
pkgs.runCommand "fluxdown-config-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    results = builtins.toJSON results;
  }
  ''
    python3 ${./fluxdown-config-test.py} "$results"
    touch "$out"
  ''
