{ lib, pkgs, ... }:
{
  # Reference: linyinfeng/dotfiles, nixos/profiles/boot/plymouth.
  # BGRT uses the firmware logo and built-in spinner, not a compositor theme.
  boot.kernelParams = [ "quiet" ];
  boot.plymouth = {
    enable = true;
    theme = lib.mkDefault "bgrt";
    font = lib.mkDefault "${pkgs.nerd-fonts.iosevka-term-slab}/share/fonts/truetype/NerdFonts/IosevkaTermSlab/IosevkaTermSlabNerdFontMono-Regular.ttf";
  };
}
