{
  pkgs,
  lib,
  config,
  ...
}: {
  fonts.fontDir.enable = true;

  fonts.packages = with pkgs;
    lib.mkForce [
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          "FiraMono"
          "Noto"
          "Terminus"
          "JetBrainsMono"
        ];
      })

      jetbrains-mono
      corefonts
      fira-code
      fira-code-symbols
      font-awesome
      config.nur.repos.xddxdd.kaixinsong-fonts
      hanazono
      config.nur.repos.xddxdd.hoyo-glyphs
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      noto-fonts-emoji-blob-bin
      noto-fonts-extra
      config.nur.repos.xddxdd.plangothic-fonts.allideo
      source-code-pro
      source-han-code-jp
      source-han-mono
      source-han-sans
      source-han-serif
      source-sans
      source-sans-pro
      source-serif
      source-serif-pro
      terminus_font_ttf
      vistafonts
      vistafonts-chs
      vistafonts-cht
      wqy_microhei
      wqy_zenhei
      powerline-fonts
      sarasa-gothic
    ];

  # https://keqingrong.cn/blog/2019-10-01-how-to-display-all-chinese-characters-on-the-computer/
  fonts.fontconfig = let
    sansFallback = [
      "Plangothic P1"
      "Plangothic P2"
      "HanaMinA"
      "HanaMinB"
    ];
    serifFallback = [
      "HanaMinA"
      "HanaMinB"
      "Plangothic P1"
      "Plangothic P2"
    ];
  in {
    defaultFonts = rec {
      emoji = ["Blobmoji" "Noto Color Emoji"];
      serif = ["Noto Serif" "Source Han Serif SC"] ++ emoji ++ serifFallback;
      sansSerif = ["Source Han Sans SC"] ++ emoji ++ sansFallback;
      monospace = ["JetBrainsMono Nerd Font" "Sarasa Mono Slab SC" "Noto Sans Mono CJK SC"] ++ emoji ++ sansFallback;
      # serif = lib.mkBefore ["Noto Serif" "Source Han Serif SC"] ++ serifFallback;
      # sansSerif = lib.mkBefore ["JetBrains Nerd Font" "Source Han Sans SC"] ++ sansFallback;
      # monospace = lib.mkBefore ["JetBrainsMono Nerd Font" "Noto Sans Mono CJK SC"] ++ sansFallback;
    };
  };
}
