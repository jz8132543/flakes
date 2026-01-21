{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;
    policies = {
      PasswordManagerEnabled = false;
      DisableFirefoxAccounts = true;
      DisablePocket = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      Preferences = {
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.urlbar.autoFill.adaptiveHistory.enabled" = true;
        "browser.tabs.closeWindowWithLastTab" = false;
        # "media.peerconnection.enabled" = false;
      };
      ExtensionSettings = {
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
        };
        # "switchyomega@feliscatus.addons.mozilla.org" = {
        #   installation_mode = "force_installed";
        #   install_url = "https://addons.mozilla.org/firefox/downloads/latest/switchyomega/latest.xpi";
        # };
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };
        "aria2-integration" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/aria2-integration/latest.xpi";
        };
      };
    };
    search = {
      default = "SearXNG";
      engines = {
        "SearXNG" = {
          loadPath = "[https]searx.dora.im/sams-searxng.xml";
          description = "SearXNG is a metasearch engine that respects your privacy.";
          urls = [
            {
              rels = [ "results" ];
              template = "https://searx.dora.im/search";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
            {
              rels = [ "suggestions" ];
              template = "https://searx.dora.im/autocompleter";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
              "type" = "application/x-suggestions+json";
            }
          ];
          # icon = engine-logos + /searx.svg;
          definedAliases = [ "@s" ];
        };

        "LibRedirect" = {
          loadPath = "[other]addEngineWithDetails:7esoorv3@alefvanoon.anonaddy.me";
          description = "A web extension that redirects popular sites to alternative privacy-friendly frontends and backends";
          urls = [
            {
              template = "https://search.libredirect.invalid/";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          # icon engine-logos + /libredirect.png;
          iconMapObj = {
            "16" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-16.png";
            "32" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-32.png";
            "48" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-48.png";
            "64" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-64.png";
            "96" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-96.png";
            "128" = "moz-extension://e115e8c0-56ce-4709-b20b-6185524b5fc9/assets/images/libredirect-128.png";
          };
          definedAliases = [ "@lb" ];
          _extensionID = "7esoorv3@alefvanoon.anonaddy.me";
        };

        "wikipedia".metaData.alias = "@w";

        "ddg".metaData.alias = "@ddg";

        "GitHub" = {
          urls = [
            {
              template = "https://github.com/search";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          # icon = engine-logos + /github.svg;
          definedAliases = [ "@gh" ];
        };

        "Nix Packages" = {
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "channel";
                  value = "unstable";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };

        "NixOS Wiki" = {
          urls = [
            {
              template = "https://nixos.wiki/index.php";
              params = [
                {
                  name = "search";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@nw" ];
        };

        "Nixpkgs Issues" = {
          urls = [
            {
              template = "https://github.com/NixOS/nixpkgs/issues";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [
            "@ni"
          ];
        };

        # The urls are not changed since LibRedirect will manage the instances part
        "LibReddit" = {
          urls = [
            {
              template = "https://www.reddit.com/search";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          # icon = engine-logos + /libreddit.svg;
          definedAliases = [ "@r" ];
        };

        "Invidious" = {
          urls = [
            {
              template = "https://www.youtube.com/results";
              params = [
                {
                  name = "search_query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          # icon = engine-logos + /invidious.svg;
          definedAliases = [ "@i" ];
        };
      };
    };
  };
  home.global-persistence = {
    directories = [
      ".mozilla"
    ];
  };
}
