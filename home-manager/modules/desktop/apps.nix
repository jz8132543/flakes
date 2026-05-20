{
  lib,
  pkgs,
  ...
}:
let
  wpsTemplateRoot = ../../../conf/wps;
  writerTemplate = wpsTemplateRoot + "/Normal.dotm";
  sheetTemplate = wpsTemplateRoot + "/Normal.xltx";
  slidesTemplate = wpsTemplateRoot + "/Normal.pot";
in
{
  home.packages = with pkgs; [
    telegram-desktop
    ffmpeg
    thunderbird
    kdePackages.okular
    # nur.repos.fym998.wpsoffice-cn-fcitx
    # nur.repos.xddxdd.baidupcs-go
    # nur.repos.xddxdd.wechat-uos
    remmina
    element-desktop
    nheko
    linux-wifi-hotspot
    distrobox
    man-pages
    man-pages-posix
    # APPS
    logseq
    obsidian
    zotero
    libreoffice
    teamspeak6-client
    mumble
    jellyfin-desktop
    wechat
    antigravity-fhs
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

  home.file = lib.mkMerge [
    {
      ".config/Kingsoft/Office.conf".source = pkgs.writeText "wps-office.conf" ''
        [6.0]
        FirstInstall=0
        common\AcceptedEULA=true
        common\newInstall=false
        wpsoffice\Application%20Settings\UpdateRecoverCheckTag=false

        [kdcsdk]
        NotFirstOpen=true

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
    }
    (lib.optionalAttrs (builtins.pathExists writerTemplate) {
      ".local/share/Kingsoft/office6/templates/wps/en_US/Normal.dotm".source = writerTemplate;
    })
    (lib.optionalAttrs (builtins.pathExists sheetTemplate) {
      ".local/share/Kingsoft/office6/templates/et/en_US/Normal.xltx".source = sheetTemplate;
    })
    (lib.optionalAttrs (builtins.pathExists slidesTemplate) {
      ".local/share/Kingsoft/office6/templates/wpp/en_US/Normal.pot".source = slidesTemplate;
    })
  ];

  xdg.desktopEntries = {
    wps-writer = {
      name = "WPS 文字";
      genericName = "WPS Writer";
      comment = "Open WPS Writer";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "wps"} ${writerTemplate}";
      icon = "wps-office2023-wpsmain";
      terminal = false;
      categories = [
        "Office"
        "WordProcessor"
      ];
    };
    wps-spreadsheet = {
      name = "WPS 表格";
      genericName = "WPS Spreadsheets";
      comment = "Open WPS Spreadsheets";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "et"} ${sheetTemplate}";
      icon = "wps-office2023-etmain";
      terminal = false;
      categories = [
        "Office"
        "Spreadsheet"
      ];
    };
    wps-presentation = {
      name = "WPS 演示";
      genericName = "WPS Presentation";
      comment = "Open WPS Presentation";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "wpp"} ${slidesTemplate}";
      icon = "wps-office2023-wppmain";
      terminal = false;
      categories = [
        "Office"
        "Presentation"
      ];
    };
  };

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
      ".config/obsidian"
      ".local/share/obsidian"
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
