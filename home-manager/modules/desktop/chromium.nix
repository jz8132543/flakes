{ ... }:
let
  browser = [
    "chromium-browser.desktop"
    "chromium.desktop"
  ];
  associations = {
    "text/html" = browser;
    "x-scheme-handler/http" = browser;
    "x-scheme-handler/https" = browser;
    "x-scheme-handler/ftp" = browser;
    "x-scheme-handler/chrome" = browser;
    "x-scheme-handler/about" = browser;
    "x-scheme-handler/unknown" = browser;
    "application/x-extension-htm" = browser;
    "application/x-extension-html" = browser;
    "application/x-extension-shtml" = browser;
    "application/xhtml+xml" = browser;
    "application/x-extension-xhtml" = browser;
    "application/x-extension-xht" = browser;
    "application/json" = browser; # ".json"  JSON format
    "application/pdf" = browser; # ".pdf"  Adobe Portable Document Format (PDF)
  };
in
{
  xdg.mimeApps.enable = true;
  xdg.mimeApps.associations.added = associations;
  xdg.mimeApps.defaultApplications = associations;
  programs.chromium = {
    enable = true;
    # package = pkgs.chromium;
    extensions = [
      # "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      # "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
      # "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
      # PT-Depiler - PT站点效率工具（聚合搜索、一键下载到qBittorrent等）
      "gfkgnjfipffpfdnfmcpaoajkidapcplc"
      # CookieCloud - 同步PT站点Cookie
      "ffjiejobkoibkjlhjnlgmcnnigeelbdl"
      # Linkwarden - Bookmark Manager
      "efpglpohdfnodejoimcladancmgeibao"
    ];
    # https://wiki.archlinux.org/title/Chromium#Native_Wayland_support
    # commandLineArgs = [
    #   "--ozone-platform-hint=auto"
    #   "--ozone-platform=wayland"
    #   # make it use GTK_IM_MODULE if it runs with Gtk4, so fcitx5 can work with it.
    #   # (only supported by chromium/chrome at this time, not electron)
    #   "--gtk-version=4"
    #   # make it use text-input-v1, which works for kwin 5.27 and weston
    #   # "--enable-wayland-ime"
    #
    #   # enable hardware acceleration - vulkan api
    #   # "--enable-features=Vulkan"
    # ];
  };
  # programs.chromium = {
  #   enable = true;
  #   extensions = [
  #     "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
  #     "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
  #     "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
  #     "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
  #     # "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
  #   ];
  # };
  home.global-persistence = {
    directories = [
      ".config/chromium"
      ".cache/chromium"
    ];
  };
  home.file.".config/google-chrome/policies/managed/policy.json".text = builtins.toJSON {
    "3rdparty" = {
      "extensions" = {
        "ffjiejobkoibkjlhjnlgmcnnigeelbdl" = {
          "host" = "https://cookiecloud.dora.im";
        };
        "efpglpohdfnodejoimcladancmgeibao" = {
          "host" = "https://link.dora.im";
        };
      };
    };
  };
}
