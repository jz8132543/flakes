{
  pkgs,
  lib,
  ...
}:
{
  fonts = {
    enableDefaultPackages = true;
    fontDir = {
      enable = true;
      decompressFonts = true;
    };
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.symbols-only
      nerd-fonts.roboto-mono
      windows-fonts
      vista-fonts
      material-design-icons
      material-symbols
      font-awesome
      # Steam
      # source-han-serif
      # source-han-sans
      # wqy_zenhei
      # wqy_microhei
      # foundertypeFonts.combine
      # (
      #   font:
      #   (lib.attrByPath [
      #     "meta"
      #     "license"
      #     "shortName"
      #   ] "unknown" font) == "foundertype-per-ula"
      # )
      # foundertypeFonts.fzlsk
      # foundertypeFonts.fzxbsk
      # foundertypeFonts.fzxh1k
      # foundertypeFonts.fzy1k
      # foundertypeFonts.fzy3k
      # foundertypeFonts.fzy4k
    ];
    fontconfig.defaultFonts = pkgs.lib.mkForce {
      serif = [
        "Noto Serif"
        "Noto Serif CJK SC"
      ];
      sansSerif = [
        "Noto Sans"
        "Noto Sans CJK SC"
      ];
      monospace = [ "JetBrains Mono" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
