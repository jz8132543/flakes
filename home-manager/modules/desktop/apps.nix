{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    telegram-desktop
    ffmpeg
    thunderbird
    kdePackages.okular
    nur.repos.fym998.wpsoffice-cn-fcitx
    # nur.repos.xddxdd.baidupcs-go
    # nur.repos.xddxdd.wechat-uos
    remmina
    element-desktop
    linux-wifi-hotspot
    distrobox
    man-pages
    man-pages-posix
    # APPS
    logseq
    zotero
    libreoffice
    teamspeak6-client
    mumble
    jellyfin-desktop
    wechat-uos
    google-antigravity
    google-chrome
    code-cursor
    codex
    gnome-connections
    # CD/DVD Burning
    kdePackages.k3b
    vcdimager
    cdrtools
    dvdplusrwtools
  ];
  programs = {
    # TODO
    # gitui = {
    #   enable = true;
    #   keyConfig = builtins.readFile ./key_bindings.ron;
    #   theme = builtins.readFile "${localFlake'.packages.catppuccin-gitui}/share/gitui/catppuccin-macchiato.ron";
    # };
    intelli-shell = {
      enable = true;
    };
    # Document viewer
    zathura = {
      enable = true;
      options = {
        selection-clipboard = "clipboard";
        scroll-page-aware = "true";
        scroll-full-overlap = "0.01";
        scroll-step = "100";
      };
    };
    thunderbird = {
      enable = true;
      profiles = {
        default = {
          isDefault = true;
          search = {
            force = true;
            default = "ddg";
            privateDefault = "ddg";
          };
        };
      };
    };
    yt-dlp = {
      enable = true;
      settings = {
        audio-format = "best";
        audio-quality = 0;
        embed-chapters = true;
        embed-metadata = true;
        embed-subs = true;
        embed-thumbnail = true;
        remux-video = "aac>m4a/mov>mp4/mkv";
        sponsorblock-mark = "sponsor";
        sub-langs = "all";
      };
    };
    tealdeer = {
      enable = true;
      settings = {
        display = {
          use_pager = true;
          compact = true;
        };
        updates = {
          auto_update = true;
          auto_update_interval_hours = 168;
        };
      };
    };
  };
  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        charset = "utf-8";
        end_of_line = "lf";
        insert_final_newline = true;
        trim_trailing_whitespace = true;
        indent_style = "space";
      };
      "*.nix" = {
        indent_size = 2;
      };
      "*.lua" = {
        indent_size = 3;
      };
      "*.typ" = {
        indent_size = 2;
      };
      "*.c" = {
        indent_size = 2;
      };
      "{Makefile,makefile}" = {
        indent_style = "tab";
      };
    };
  };
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu+ssh://tippy@shg0:22/system" ];
      uris = [
        "qemu+ssh://tippy@shg0:22/system"
        "qemu:///system"
      ];
    };
    "org/virt-manager/virt-manager/vmlist-fields" = {
      disk-usage = true;
      network-traffic = true;
    };
  };
  home.activation.wpsOfficeConf =
    let
      officeConf = pkgs.writeText "wps-office.conf" ''
        [6.0]
        FirstInstall=0

        [General]
        language=zh_CN
        languages=zh_CN

        [common]
        first_run=false
        first_detect_file_association_while_startup=false
        agreementshown=true
        agree_privacy_policy=true
        agreeEULA=true
      '';
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.config/Kingsoft"
      conf="$HOME/.config/Kingsoft/Office.conf"

      if [ ! -f "$conf" ]; then
        cp -f ${officeConf} "$conf"
        chmod 0644 "$conf"
      fi

      upsert_ini_key() {
        section="$1"
        key="$2"
        value="$3"
        tmp="$(mktemp)"

        awk -v section="$section" -v key="$key" -v value="$value" '
          BEGIN {
            in_section = 0
            section_found = 0
            key_done = 0
          }

          /^\[[^]]+\]$/ {
            if (in_section && !key_done) {
              print key "=" value
              key_done = 1
            }

            if ($0 == "[" section "]") {
              in_section = 1
              section_found = 1
            } else {
              in_section = 0
            }

            print
            next
          }

          {
            if (in_section && $0 ~ ("^" key "=")) {
              if (!key_done) {
                print key "=" value
                key_done = 1
              }
              next
            }
            print
          }

          END {
            if (!key_done) {
              if (!section_found) {
                print "[" section "]"
              }
              print key "=" value
            }
          }
        ' "$conf" > "$tmp"

        mv "$tmp" "$conf"
      }

      upsert_ini_key "6.0" "FirstInstall" "0"
      upsert_ini_key "General" "language" "zh_CN"
      upsert_ini_key "General" "languages" "zh_CN"
      upsert_ini_key "common" "first_run" "false"
      upsert_ini_key "common" "first_detect_file_association_while_startup" "false"
      upsert_ini_key "common" "agreementshown" "true"
      upsert_ini_key "common" "agree_privacy_policy" "true"
      upsert_ini_key "common" "agreeEULA" "true"

      chmod 0644 "$conf"
    '';

  # Set Chrome environment variables for Playwright/browser integration
  home.sessionVariables = {
    CHROME_BIN = "${pkgs.google-chrome}/bin/google-chrome-stable";
    CHROME_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
  };
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/weixin"
      ".local/share/Kingsoft"
      ".config/Kingsoft"
      ".config/Element"
      ".logseq"
      ".config/Logseq"
      "Zotero"
      ".zotero"
      # google ai editor (antigravity)
      ".config/Antigravity"
      ".antigravity"
      ".gemini"
      ".antigravity-server"
      ".config/opencode"
      ".local/share/opencode"
      ".opencode"
      ".codex"
      ".local/share/connections"
      ".config/connections"
      ".cache/connections"
      ".local/share/remmina"
      ".config/remmina"
      ".config/libreoffice"
      ".config/google-chrome"
      ".cache/google-chrome"
      ".config/Mumble"
      ".config/TeamSpeak"
      ".config/jellyfin-desktop"
      ".config/Cursor"
      ".cache/Cursor"
      ".local/share/okular"
      ".config/linux-wifi-hotspot"
      ".config/zathura"
      ".local/share/zathura"
      ".config/dconf"
    ];
    files = [
      ".config/monitors.xml"
    ];
  };
}
