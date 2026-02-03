{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    telegram-desktop
    ffmpeg
    thunderbird
    kdePackages.okular
    wpsoffice-cn
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
    wechat-uos
    antigravity
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
    ];
    files = [
      ".config/monitors.xml"
    ];
  };
}
