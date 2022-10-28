{ config, pkgs, lib, ... }:

lib.mkIf config.environment.graphical.enable{
  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji

    source-serif
    source-han-serif
    source-sans
    source-han-sans
    source-code-pro

    jetbrains-mono
    (nerdfonts.override { fonts = [ "JetBrainsMono" "Noto" ]; })
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkBefore [ 
      "Source Sans 3"
      "Source Han Sans SC"
      "Source Han Sans TC"
      "Source Han Sans HW"
      "Source Han Sans K"
      "Noto Sans"
      "Noto Sans CJK SC"
    ];
    serif = lib.mkBefore [
      "Source Serif 4"
      "Source Han Serif SC"
      "Source Han Serif TC"
      "Source Han Serif HW"
      "Source Han Serif K"
      "Noto Serif"
      "Noto Serif CJK SC"
    ];
    monospace = lib.mkAfter [ "JetBrains Mono" ];
    emoji = lib.mkBefore [ "Noto Color Emoji" ];
  };
}
