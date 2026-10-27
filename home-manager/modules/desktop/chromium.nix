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
      "mpkodccbngfoacfalldjimigihfbocjn" # Aria2 Explorer
      # Linkwarden - Bookmark Manager
      "efpglpohdfnodejoimcladancmgeibao"
      # Zotero Connector - 一键抓取文献与PDF附件
      "ekhagklcjbdpajgpjgmbionohlpdbjgc"
      # Auto Tab Discard - 智能休眠标签页节省内存
      "jhnleheckmknfcgijgkadoemagpecfol"
    ];
    commandLineArgs = [
      # 1. 原生 Wayland 与手势导航
      "--ozone-platform-hint=auto"
      "--ozone-platform=wayland"

      # 2. 中文输入法适配 (Fcitx5 光标跟随)
      "--gtk-version=4"

      # 3. GPU 硬解与图形加速
      "--enable-gpu-rasterization"
      "--enable-zero-copy"

      # 4. 进程与内存优化（同域名合并进程节省内存）
      "--process-per-site"

      # 5. 网络抗丢包与长连接防断（禁用 QUIC 避免 UDP 443 丢包导致的大模型流式输出中断）
      "--disable-quic"
      "--enable-tcp-fastopen"

      # 6. 特性开关集合（合并避免多条 --enable-features 相互覆盖）
      "--enable-features=TouchpadOverscrollHistoryNavigation,VaapiVideoDecodeLinuxGL,VaapiVideoEncoderLinuxGL,VaapiIgnoreDriverChecks,ParallelDownloading"
    ];
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
}
