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
  wpsAssociations = {
    # WPS Writer (Word)
    "application/msword" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/vnd.ms-word.document.macroEnabled.12" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/vnd.ms-word" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/msword-template" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.doc" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.docx" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.wps" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.wpt" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.dot" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.dotx" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uot3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uott3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uot" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uos" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uos3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uost3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uop" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uop3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.uopt3" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/x-msword" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/rtf" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.msg" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.eml" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.wpso" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "application/wps-office.wpss" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "x-scheme-handler/ksoqing" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "x-scheme-handler/ksowps" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "x-scheme-handler/ksowebstartupwps" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "x-scheme-handler/ksodoccenter" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];
    "x-scheme-handler/ksowpscloudsvr" = [
      "wps-office-wps.desktop"
      "wps-writer.desktop"
    ];

    # WPS Spreadsheet (Excel)
    "application/vnd.ms-excel" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/msexcel" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/vnd.ms-excel.sheet.macroEnabled.12" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.xls" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.xlsx" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.xlt" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.xltx" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.et" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.ett" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.ets" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/wps-office.eto" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "application/x-msexcel" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "x-scheme-handler/ksoet" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];
    "x-scheme-handler/ksowebstartupet" = [
      "wps-office-et.desktop"
      "wps-spreadsheet.desktop"
    ];

    # WPS Presentation (PowerPoint)
    "application/vnd.ms-powerpoint" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/mspowerpoint" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/powerpoint" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/vnd.mspowerpoint" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/vnd.ms-powerpoint.presentation.macroEnabled.12" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.presentationml.template" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.ppt" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.pptx" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.pot" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.potx" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.dps" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.dpt" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.dpss" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/wps-office.dpso" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "application/x-mspowerpoint" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "x-scheme-handler/ksowpp" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];
    "x-scheme-handler/ksowebstartupwpp" = [
      "wps-office-wpp.desktop"
      "wps-presentation.desktop"
    ];

    # WPS PDF Internal MIME (DOES NOT affect real application/pdf, only satisfies WPS startup health checks)
    "application/wps-office.pdf" = [ "wps-office-pdf.desktop" ];
  };
in
{
  imports = [ ./obsidian-livesync.nix ];

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
    # logseq
    obsidian
    zotero
    libreoffice
    teamspeak6-client
    mumble
    jellyfin-desktop
    wechat
    antigravity-ide-fhs
    google-chrome
    code-cursor
    codex
    gnome-connections
    # CD/DVD Burning is configured system-wide via programs.k3b.
    # kdePackages.k3b
    # vcdimager
    feishu
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
        common\first_run=false
        common\do_not_detect_file_association_while_startup=true
        common\first_detect_file_association_while_startup=false
        common\check_file_association=false
        common\FileAssociationFixRemind=false
        wpsoffice\Application%20Settings\CheckFileAssociation=false
        wpsoffice\Application%20Settings\FileAssociationFixRemind=false
        wpsoffice\Application%20Settings\WordFileAssociation=false
        wpsoffice\Application%20Settings\ExcelFileAssociation=false
        wpsoffice\Application%20Settings\PowerPntFileAssociation=false
        wpsoffice\Application%20Settings\PictureFileAssociation=false
        wpsoffice\Application%20Settings\RbFileAssociation=false
        wpsoffice\Application%20Settings\UpdateRecoverCheckTag=false
        wpsoffice\Application%20Settings\PromptUpdateStyle=0
        wpsoffice\Application%20Settings\UpdateLinksAtOpen=0
        wpsoffice\Application%20Settings\UpdateFieldsAtPrint=0
        wpsoffice\Application%20Settings\UpdateLinksAtPrint=0
        wpsoffice\Application%20Settings\UpdateFieldsWithTrackedChangesAtPrint=0

        [kdcsdk]
        NotFirstOpen=true

        [General]
        language=zh_CN
        languages=zh_CN

        [common]
        first_run=false
        do_not_detect_file_association_while_startup=true
        first_detect_file_association_while_startup=false
        check_file_association=false
        FileAssociationFixRemind=false
        WordFileAssociation=false
        ExcelFileAssociation=false
        PowerPntFileAssociation=false
        PictureFileAssociation=false
        RbFileAssociation=false
        agreementshown=true
        agree_privacy_policy=true
        agreeEULA=true

        [wpsoffice\Application%20Settings]
        CheckFileAssociation=false
        FileAssociationFixRemind=false
        WordFileAssociation=false
        ExcelFileAssociation=false
        PowerPntFileAssociation=false
        PictureFileAssociation=false
        RbFileAssociation=false

        [wps\Application%20Settings]
        CheckFileAssociation=false
        FileAssociationFixRemind=false
        WordFileAssociation=false

        [et\Application%20Settings]
        EnableFormatCheck=0
        AskToUpdateLinks=0
        CheckFileAssociation=false
        FileAssociationFixRemind=false
        ExcelFileAssociation=false

        [wpp\Application%20Settings]
        CheckFileAssociation=false
        FileAssociationFixRemind=false
        PowerPntFileAssociation=false

        [pdf\Application%20Settings]
        CheckFileAssociation=false
        FileAssociationFixRemind=false

        [UnixUpdateInfo]
        UserRejectUpdateVersion=${pkgs.wpsoffice-cn.version}
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

  xdg.mimeApps = {
    enable = true;
    associations.added = wpsAssociations;
    defaultApplications = wpsAssociations;
  };

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
      "Sync/.obsidian"
      "Sync/.livesync"
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
      ".codex"
    ];
    files = [
      ".config/monitors.xml"
    ];
  };
}
