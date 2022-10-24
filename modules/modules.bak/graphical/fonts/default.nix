{ config, pkgs, lib, ... }:

let
  iosevka-dora = pkgs.iosevka.override {
    privateBuildPlan = {
      family = "Iosevka Dora";
      spacing = "fontconfig-mono";
      serifs = "slab";
      # no need to export character variants and stylistic set
      no-cv-ss = "true";
      ligations = {
        inherits = "haskell";
      };
    };
    set = "dora";
  };
in
lib.mkIf config.hardware.graphical.enable{
  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji

    source-serif
    source-han-serif
    source-sans
    source-han-sans
    source-code-pro

    open-sans
    liberation_ttf
    wqy_zenhei
    wqy_microhei

    jetbrains-mono
    iosevka-dora
    font-awesome
    powerline-fonts
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkBefore [
      "Source Sans 3"
      "Source Han Sans SC"
      "Source Han Sans TC"
      "Source Han Sans HW"
      "Source Han Sans K"
    ];
    serif = lib.mkBefore [
      "Source Serif 4"
      "Source Han Serif SC"
      "Source Han Serif TC"
      "Source Han Serif HW"
      "Source Han Serif K"
    ];
    monospace = lib.mkAfter [
      "JetBrains Mono"
      "Iosevka Dora"
    ];
    emoji = lib.mkBefore [
      "Noto Color Emoji"
    ];
  };

  passthru = { inherit iosevka-dora; };
}
