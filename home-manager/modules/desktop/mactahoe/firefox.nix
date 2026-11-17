{
  config,
  lib,
  pkgs,
  ...
}:
let
  firefox = config.programs.firefox;
  assets = "${pkgs.mactahoe.firefox}/share/mactahoe/firefox";
  chrome = ''
    @import url("file://${assets}/userChrome.css");
  '';
  content = ''
    @import url("file://${assets}/userContent.css");
  '';
  preferences = {
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    "browser.tabs.drawInTitlebar" = true;
    "browser.uidensity" = 0;
    "svg.context-properties.content.enabled" = true;
    # Keep browser chrome and websites light, independent of desktop theme changes.
    "layout.css.prefers-color-scheme.content-override" = 1;
    "browser.theme.content-theme" = 1;
    "browser.theme.toolbar-theme" = 1;
  };
  profileRoot =
    if lib.hasPrefix "/" firefox.profilesPath then
      firefox.profilesPath
    else
      "${config.home.homeDirectory}/${firefox.profilesPath}";
  managedProfiles = map (profile: "${profileRoot}/${profile.path}") (
    builtins.attrValues firefox.profiles
  );
in
{
  # Extend each declared profile without creating one or replacing its registration.
  options.programs.firefox.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config = lib.mkIf firefox.enable {
          settings = lib.mapAttrs (_: value: lib.mkDefault value) preferences;
          userChrome = lib.mkBefore chrome;
          userContent = lib.mkBefore content;
        };
      }
    );
  };

  config = lib.mkIf firefox.enable {
    programs.firefox.policies.Preferences = lib.mapAttrs (name: value: {
      Value = value;
      Status =
        if
          lib.elem name [
            "toolkit.legacyUserProfileCustomizations.stylesheets"
            "layout.css.prefers-color-scheme.content-override"
            "browser.theme.content-theme"
            "browser.theme.toolbar-theme"
          ]
        then
          "locked"
        else
          "default";
    }) preferences;

    xdg.dataFile = {
      "mactahoe-firefox/userChrome.css".text = chrome;
      "mactahoe-firefox/userContent.css".text = content;
    };

    # Existing native profiles may not be declared in HM; only link absent CSS leaves.
    home.activation.mactahoeFirefoxProfiles = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.python3}/bin/python3 -B ${./firefox.py} \
        ${lib.escapeShellArg config.home.homeDirectory} \
        ${lib.escapeShellArg firefox.profilesPath} \
        ${lib.escapeShellArg "${config.xdg.dataHome}/mactahoe-firefox"} \
        ${lib.escapeShellArg (builtins.toJSON managedProfiles)}
    '';

    home.file = lib.mkIf config.programs.firefox-apps.enable (
      lib.mkMerge (
        map (app: {
          ".mozilla/firefox-apps/${app.name}/chrome/userChrome.css".text = lib.mkBefore chrome;
          ".mozilla/firefox-apps/${app.name}/chrome/userContent.css".text = content;
        }) config.programs.firefox-apps.apps
      )
    );
  };
}
