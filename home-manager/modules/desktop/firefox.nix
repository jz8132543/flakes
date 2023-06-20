{pkgs, ...}: {
  programs.firefox = {
    enable = true;
    package = pkgs.wrapFirefox pkgs.firefox-beta-unwrapped {
      extraPolicies = {
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
        };
        ExtensionSettings = {
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          };
          "switchyomega@feliscatus.addons.mozilla.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/switchyomega/latest.xpi";
          };
          "uBlock0@raymondhill.net" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          };
        };
      };
    };
    profiles = {
      windranger = {
        isDefault = true;
        bookmarks = [
          {
            toolbar = true;
            bookmarks = [
              {
                name = "roam";
                url = "javascript:location.href ='org-protocol://roam-ref?template=b&ref='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title)+'&body='+encodeURIComponent(window.getSelection())";
              }
            ];
          }
        ];
        settings = {
          "fission.autostart" = true;
          "browser.urlbar.autoFill.adaptiveHistory.enabled" = true;
          "media.peerconnection.enabled" = false;
          "browser.aboutwelcome.enabled" = false;
          "browser.discovery.enabled" = false;
          "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" =
            false;
          "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" =
            false;
          "browser.newtabpage.activity-stream.feeds.telemetry" = false;
          "browser.newtabpage.activity-stream.telemetry" = false;

          "signon.rememberSignons" = false;

          "browser.startup.homepage" = "about:blank";
          "browser.newtabpage.enabled" = false;

          "browser.pocket.enabled" = false;
          "extensions.pocket.enabled" = false;

          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.healthreport.service.enabled" = false;
          "datareporting.policy.dataSubmissionEnabled" = false;

          "signon.management.page.breach-alerts.enabled" = false;
          "browser.safebrowsing.malware.enabled" = false;
          "browser.safebrowsing.phishing.enabled" = false;
          "browser.safebrowsing.downloads.remote.enabled" = false;

          "app.normandy.enabled" = false;
          "app.normandy.api_url" = "";
          "extensions.shield-recipe-client.enabled" = false;
          "app.shield.optoutstudies.enabled" = false;

          "extensions.update.enabled" = false;
          "toolkit.telemetry.enabled" = false;
          "browser.ping-centre.telemetry" = false;
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.bhrPing.enabled" = false;
          "toolkit.telemetry.firstShutdownPing.enabled" = false;
          "toolkit.telemetry.hybridContent.enabled" = false;
          "toolkit.telemetry.newProfilePing.enabled" = false;
          "toolkit.telemetry.reportingpolicy.firstRun" = false;
          "toolkit.telemetry.shutdownPingSender.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.updatePing.enabled" = false;
          "toolkit.telemetry.pioneer-new-studies-available" = false;

          "experiments.supported" = false;
          "experiments.enabled" = false;
          "experiments.manifest.uri" = false;
          "network.allow-experiments" = false;

          "dom.events.asyncClipboard.clipboardItem" = true;

          "browser.bookmarks.addedImportButton" = false;
          "browser.toolbars.bookmarks.visibility" = "never";

          # tuic not go through proxy rule
          "network.http.http3.enable" = false;
        };

        search = {
          force = true;

          default = "Google UK";

          engines = {
            "Google".metaData.hidden = true;
            "Wikipedia (en)".metaData.alias = "@w";

            "Google UK" = {
              urls = [
                {
                  template = "https://www.google.co.uk/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = ["@g"];
            };

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
              definedAliases = ["@gh"];
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
              definedAliases = ["@np"];
            };

            "NixOS Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
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
              definedAliases = ["@no"];
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
              definedAliases = ["@nw"];
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
              definedAliases = ["@ni"];
            };

            "Nix code" = {
              urls = [
                {
                  template = "https://github.com/search";
                  params = [
                    {
                      name = "type";
                      value = "Code";
                    }
                    {
                      name = "q";
                      value = "{searchTerms}+language%3ANix";
                    }
                  ];
                }
              ];
              definedAliases = ["@nc"];
            };

            "Reddit" = {
              urls = [
                {
                  template = "https://old.reddit.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                    {
                      name = "include_over_18";
                      value = "on";
                    }
                  ];
                }
              ];
              definedAliases = ["@r"];
            };
          };
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
