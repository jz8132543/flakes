{
  pkgs,
  lib,
  ...
}: {
  fonts = {
    fonts = with pkgs; [
      maple-mono
      maple-mono-NF
      maple-mono-SC-NF

      material-symbols
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji

      source-serif
      source-han-serif
      source-sans
      source-han-sans
      source-code-pro
    ];

    fontconfig = {
      enable = true;
      antialias = true;
      hinting = {
        enable = true;
        autohint = true;
        style = "hintfull";
      };

      subpixel.lcdfilter = "default";

      defaultFonts = {
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
        emoji = lib.mkBefore ["Noto Color Emoji"];
        monospace = lib.mkBefore ["Maple Mono NF"];
      };
    };
  };
}
