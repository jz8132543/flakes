{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.firefox-apps;

  onlineIcons = pkgs.callPackage ../../../pkgs/firefox-app-icons.nix { };

  defaultApps = [
    {
      name = "wechat-filetransfer";
      displayName = "微信文件传输助手";
      genericName = "WeChat File Transfer";
      comment = "微信网页版文件传输助手";
      url = "https://filehelper.weixin.qq.com/";
      icon = onlineIcons.wechat;
      categories = [
        "Network"
        "Chat"
        "InstantMessaging"
      ];
      minimalUI = true;
    }
    {
      name = "syncthing";
      displayName = "Syncthing";
      genericName = "File Synchronization";
      comment = "Syncthing Web 管理界面";
      url = "http://127.0.0.1:8384";
      icon = onlineIcons.syncthing;
      categories = [
        "Network"
        "FileTransfer"
      ];
      minimalUI = true;
    }
    {
      name = "doubao";
      displayName = "豆包";
      genericName = "AI Assistant";
      comment = "字节跳动 AI 对话助手";
      url = "https://www.doubao.com/chat";
      icon = onlineIcons.doubao;
      categories = [
        "Network"
        "ArtificialIntelligence"
      ];
      minimalUI = true;
    }
    {
      name = "gemini";
      displayName = "Google Gemini";
      genericName = "AI Assistant";
      comment = "Google Gemini AI";
      url = "https://gemini.google.com/app";
      icon = onlineIcons.gemini;
      categories = [
        "Network"
        "ArtificialIntelligence"
      ];
      minimalUI = true;
    }
    {
      name = "deepseek";
      displayName = "DeepSeek";
      genericName = "AI Assistant";
      comment = "DeepSeek AI 对话助手";
      url = "https://chat.deepseek.com";
      icon = onlineIcons.deepseek;
      categories = [
        "Network"
        "ArtificialIntelligence"
      ];
      minimalUI = true;
    }
  ];
in
{
  options.programs.firefox-apps = {
    enable = lib.mkEnableOption "Firefox Web Apps (SSB-like standalone desktop applications)" // {
      default = true;
    };

    apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Identifier of the application, used for profile dir and WM_CLASS / app_id.";
            };
            displayName = lib.mkOption {
              type = lib.types.str;
              description = "Human-readable display name for desktop entry.";
            };
            genericName = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Generic name for desktop entry.";
            };
            comment = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Comment / tooltip for desktop entry.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Target URL.";
            };
            icon = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.either lib.types.package (lib.types.either lib.types.path lib.types.str)
              );
              default = null;
              description = "Icon path, fetchurl package, icon theme name, or null to fallback to firefox.";
            };
            categories = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "Network"
                "Application"
              ];
            };
            minimalUI = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to hide the tab bar for a standalone app feel.";
            };
            desktopEntryExtras = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Extra attributes merged into xdg.desktopEntries.<name>.";
            };
          };
        }
      );
      default = defaultApps;
      description = "List of Firefox Web Applications.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.desktopEntries = builtins.listToAttrs (
      map (app: {
        inherit (app) name;
        value = {
          name = app.displayName;
          inherit (app) genericName;
          inherit (app) comment;
          exec = "firefox --profile ${config.home.homeDirectory}/.mozilla/firefox-apps/${app.name} --name ${app.name} --class ${app.name} ${app.url}";
          icon =
            if app.icon == null then
              "firefox"
            else if lib.isDerivation app.icon || builtins.isPath app.icon then
              "${app.icon}"
            else
              app.icon;
          terminal = false;
          inherit (app) categories;
          settings = {
            StartupWMClass = app.name;
          };
        }
        // app.desktopEntryExtras;
      }) cfg.apps
    );

    home.file = lib.mkMerge (
      map (
        app:
        {
          ".mozilla/firefox-apps/${app.name}/user.js".text = ''
            // Generated by Nix / Home Manager for Firefox App: ${app.name}
            user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.tabs.warnOnClose", false);
            user_pref("browser.tabs.closeWindowWithLastTab", true);
            user_pref("browser.startup.page", 1);
            user_pref("browser.startup.homepage", "${app.url}");
          '';
        }
        // (lib.optionalAttrs app.minimalUI {
          ".mozilla/firefox-apps/${app.name}/chrome/userChrome.css".text = ''
            /* Generated by Nix / Home Manager for Firefox App: ${app.name} */
            /* Standalone App (SSB) style: hide tab bar */
            #TabsToolbar {
              visibility: collapse !important;
            }
            #titlebar {
              appearance: none !important;
            }
          '';
        })
      ) cfg.apps
    );
  };
}
