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
  # Default handlers and desktop MimeType fields share one source of truth.
  documentMimeTypes = {
    wps-writer = [
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
      "application/msword"
      "application/vnd.ms-word"
      "application/msword-template"
      "application/x-msword"
      "application/vnd.ms-word.document.macroEnabled.12"
      "application/vnd.ms-word.template.macroEnabled.12"
      "application/rtf"
      "text/rtf"
      "application/vnd.oasis.opendocument.text"
      "application/vnd.oasis.opendocument.text-template"
      "application/wps-office.docx"
      "application/wps-office.doc"
      "application/wps-office.dot"
      "application/wps-office.dotx"
      "application/wps-office.wps"
      "application/wps-office.wpt"
      "application/kswps"
      "application/wps-office.uot"
      "application/wps-office.uot3"
      "application/wps-office.uott3"
      "application/wps-office.msg"
      "application/wps-office.eml"
      "application/wps-office.wpso"
      "application/wps-office.wpss"
      "x-scheme-handler/ksoqing"
      "x-scheme-handler/ksowps"
      "x-scheme-handler/ksowebstartupwps"
      "x-scheme-handler/ksodoccenter"
      "x-scheme-handler/ksowpscloudsvr"
    ];
    wps-spreadsheet = [
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template"
      "application/vnd.ms-excel"
      "application/msexcel"
      "application/x-msexcel"
      "application/vnd.ms-excel.sheet.macroEnabled.12"
      "application/vnd.ms-excel.template.macroEnabled.12"
      "application/vnd.ms-excel.sheet.binary.macroenabled.12"
      "application/vnd.oasis.opendocument.spreadsheet"
      "application/vnd.oasis.opendocument.spreadsheet-template"
      "text/csv"
      "application/wps-office.xlsx"
      "application/wps-office.xls"
      "application/wps-office.xlt"
      "application/wps-office.xltx"
      "application/wps-office.et"
      "application/wps-office.ett"
      "application/wps-office.ets"
      "application/wps-office.eto"
      "application/wps-office.uos"
      "application/wps-office.uos3"
      "application/wps-office.uost3"
      "x-scheme-handler/ksoet"
      "x-scheme-handler/ksowebstartupet"
    ];
    wps-presentation = [
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
      "application/vnd.openxmlformats-officedocument.presentationml.template"
      "application/vnd.ms-powerpoint"
      "application/mspowerpoint"
      "application/powerpoint"
      "application/x-mspowerpoint"
      "application/vnd.mspowerpoint"
      "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
      "application/vnd.ms-powerpoint.slideshow.macroEnabled.12"
      "application/vnd.ms-powerpoint.template.macroEnabled.12"
      "application/vnd.oasis.opendocument.presentation"
      "application/vnd.oasis.opendocument.presentation-template"
      "application/wps-office.pptx"
      "application/wps-office.ppt"
      "application/wps-office.pot"
      "application/wps-office.potx"
      "application/wps-office.dps"
      "application/wps-office.dpt"
      "application/wps-office.dpss"
      "application/wps-office.dpso"
      "application/wps-office.uop"
      "application/wps-office.uop3"
      "application/wps-office.uopt3"
      "x-scheme-handler/ksowpp"
      "x-scheme-handler/ksowebstartupwpp"
    ];
  };
  documentAssociations = lib.foldlAttrs (
    result: name: mimeTypes:
    result // lib.genAttrs mimeTypes (_: [ "${name}.desktop" ])
  ) { "application/wps-office.pdf" = [ "wps-office-pdf.desktop" ]; } documentMimeTypes;
in
{
  imports = [
    # ./storage-papers.nix (Migrated to NixOS system-level autofs)
    ./obsidian-livesync.nix
    # ./zotero.nix  # disabled due to Zotero build issues
    ./cc-switch.nix
  ];

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
    # logseq (obsidian and zotero managed in their respective dedicated modules)
    onlyoffice-desktopeditors
    typst
    tinymist
    teamspeak6-client
    mumble
    jellyfin-desktop
    wechat
    antigravity-ide-fhs
    codex
    devin-desktop
    code-cursor
    nur.repos.lonerOrz.trae

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
      # Upstream v3.4.6 bug (PR #74): `bind \c$char` causes an "Invalid token '\c$char'" syntax error on Fish 4.x.
      # Patch the embedded init template directly so official `enableFishIntegration` works cleanly.
      package = pkgs.intelli-shell.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/_shell/intelli-shell.fish \
            --replace-fail 'bind \c$char $target_func' 'eval "bind \\c$char \$target_func"'
        '';
      });
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
    (lib.optionalAttrs (builtins.pathExists writerTemplate) {
      ".local/share/Kingsoft/office6/templates/wps/zh_CN/Normal.dotm".source = writerTemplate;
    })
    (lib.optionalAttrs (builtins.pathExists sheetTemplate) {
      ".local/share/Kingsoft/office6/templates/et/zh_CN/Normal.xltx".source = sheetTemplate;
    })
    (lib.optionalAttrs (builtins.pathExists slidesTemplate) {
      ".local/share/Kingsoft/office6/templates/wpp/zh_CN/Normal.pot".source = slidesTemplate;
    })
  ];

  xdg.mimeApps = {
    enable = true;
    associations.added = documentAssociations;
    defaultApplications = documentAssociations;
  };

  xdg.desktopEntries = {
    antigravity-ide = {
      name = "Antigravity IDE";
      genericName = "Text Editor";
      exec = "antigravity-ide --password-store=basic --remote-debugging-port=9000 %F";
      icon = "antigravity-ide";
      terminal = false;
      categories = [
        "Development"
        "IDE"
        "TextEditor"
      ];
      startupNotify = true;
    };
    wps-writer = {
      mimeType = documentMimeTypes.wps-writer;
      name = "WPS 文字";
      genericName = "WPS Writer";
      comment = "Open WPS Writer";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "wps"} %F";
      icon = "wps-office2023-wpsmain";
      terminal = false;
      categories = [
        "Office"
        "WordProcessor"
      ];
    };
    wps-spreadsheet = {
      mimeType = documentMimeTypes.wps-spreadsheet;
      name = "WPS 表格";
      genericName = "WPS Spreadsheets";
      comment = "Open WPS Spreadsheets";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "et"} %F";
      icon = "wps-office2023-etmain";
      terminal = false;
      categories = [
        "Office"
        "Spreadsheet"
      ];
    };
    wps-presentation = {
      mimeType = documentMimeTypes.wps-presentation;
      name = "WPS 演示";
      genericName = "WPS Presentation";
      comment = "Open WPS Presentation";
      exec = "${lib.getExe' pkgs.wpsoffice-cn "wpp"} %F";
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
      ".local/share/keyrings"
      # google ai editor (antigravity)
      ".config/Antigravity"
      ".config/Antigravity IDE"
      ".antigravity"
      ".antigravity-ide"
      ".gemini"
      ".pki"
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
      ".config/onlyoffice"
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
      ".config/Devin"
      ".devin"
      ".local/share/Devin"
    ];
    files = [
      # ".config/monitors.xml" # Removed to allow GNOME to adaptively configure monitors based on EDID
    ];
  };

  # home.activation.extractMs365Icons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #       OFFICE_DIR="$HOME/.local/share/ms365/prefix/drive_c/Program Files/Microsoft Office/root/Office16"
  #       ICONS_DIR="$HOME/.local/share/icons/hicolor"
  #       if [ -d "$OFFICE_DIR" ] && [ ! -f "$ICONS_DIR/256x256/apps/ms365-word.png" ]; then
  #         tmp=$(${pkgs.coreutils}/bin/mktemp -d)
  #         for app in word excel powerpoint onenote outlook access publisher; do
  #           case "$app" in
  #             word) exe="WINWORD" ;; excel) exe="EXCEL" ;; powerpoint) exe="POWERPNT" ;;
  #             onenote) exe="ONENOTE" ;; outlook) exe="OUTLOOK" ;; access) exe="MSACCESS" ;; publisher) exe="MSPUB" ;;
  #           esac
  #           name="ms365-$app"
  #           group=$(${pkgs.icoutils}/bin/wrestool -l -t 14 "$OFFICE_DIR/$exe.EXE" 2>/dev/null | ${pkgs.coreutils}/bin/head -1 | ${pkgs.gnused}/bin/sed -n "s/.*--name=\([^ ]*\).*/\1/p")
  #           if [ -n "$group" ] && ${pkgs.icoutils}/bin/wrestool -x -t 14 -n "$group" -o "$tmp/$app.ico" "$OFFICE_DIR/$exe.EXE" 2>/dev/null; then
  #             ${pkgs.python3}/bin/python3 - "$tmp/$app.ico" "$ICONS_DIR" "$name" << "PY"
  #   import os, struct, sys
  #   ico, icons_dir, name = sys.argv[1:]
  #   data = open(ico, "rb").read()
  #   for i in range(struct.unpack_from("<H", data, 4)[0]):
  #       w, h, _, _, _, _, size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
  #       w, img = w or 256, data[off:off + size]
  #       if w in (16, 24, 32, 48, 64, 128, 256) and w == (h or 256) and img[:8] == b"\x89PNG\r\n\x1a\n":
  #           path = os.path.join(icons_dir, f"{w}x{w}", "apps", f"{name}.png")
  #           os.makedirs(os.path.dirname(path), exist_ok=True)
  #           open(path, "wb").write(img)
  #   PY
  #           fi
  #         done
  #         ${pkgs.coreutils}/bin/rm -rf "$tmp"
  #         ${pkgs.gtk3}/bin/gtk-update-icon-cache -q -t "$ICONS_DIR" 2>/dev/null || true
  #       fi
  # '';
}
