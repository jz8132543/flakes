{
  config,
  lib,
  pkgs,
  ...
}:
let
  font = "${pkgs.dejavu_fonts.minimal}/share/fonts/truetype/DejaVuSans.ttf";
  startup =
    pkgs.runCommand "mactahoe-startup"
      {
        nativeBuildInputs = [
          pkgs.grub2
          pkgs.imagemagick
        ];
        meta = {
          description = "Original monochrome Summit Plymouth and Tahoe-night GRUB integration";
          license = [ lib.licenses.mit ] ++ lib.toList pkgs.dejavu_fonts.meta.license;
          platforms = lib.platforms.linux;
        };
      }
      ''
        plymouth="$out/share/plymouth/themes/mactahoe"
        grub="$out/share/grub/themes/mactahoe"
        mkdir -p "$plymouth" "$grub" "$out/share/doc/mactahoe-startup"
        cp ${./assets/LICENSE} "$out/share/doc/mactahoe-startup/LICENSE"
        cp ${pkgs.mactahoe.wallpaper}/share/doc/mactahoe-wallpaper/COPYING \
          "$out/share/doc/mactahoe-startup/WALLPAPER-LICENSE"
        cp ${pkgs.dejavu_fonts.full-ttf.src}/LICENSE \
          "$out/share/doc/mactahoe-startup/FONT-LICENSE"
        cp ${./assets/summit.svg} "$plymouth/summit.svg"
        magick -background none ${./assets/summit.svg} "$plymouth/logo.png"
        magick -size 220x4 xc:white "$plymouth/progress.png"
        cp ${./assets/mactahoe.script} "$plymouth/mactahoe.script"
        substitute ${./assets/mactahoe.plymouth} "$plymouth/mactahoe.plymouth" \
          --replace-fail '@THEME_DIR@' "$plymouth"

        cp ${./assets/grub-theme.txt} "$grub/theme.txt"
        grub-mkfont --size=18 --name="DejaVu Sans" ${font} -o "$grub/font.pf2"
        magick ${pkgs.mactahoe.wallpaper}/share/wallpapers/MacTahoe/MacTahoe-night.jpeg \
          -resize '1920x1080^' -gravity center -extent 1920x1080 \
          -fill black -colorize 30 -depth 8 "$grub/background.png"
        magick -background none ${./assets/selection.svg} "$TMPDIR/selection.png"
        # GRUB scales a nine-slice box without stretching its rounded corners.
        names=(nw n ne w c e sw s se)
        for index in "''${!names[@]}"; do
          x=$(( (index % 3) * 9 ))
          y=$(( (index / 3) * 9 ))
          magick "$TMPDIR/selection.png" -crop "9x9+$x+$y" +repage \
            "$grub/selected_''${names[$index]}.png"
        done
      '';
in
{
  desktop.mactahoe.startupPackage = startup;
  boot = {
    # Keep the original animation available via boot.plymouth.theme = "mactahoe".
    plymouth = lib.mkIf (config.boot.plymouth.theme == "mactahoe") {
      themePackages = [ startup ];
      inherit font;
      logo = "${startup}/share/plymouth/themes/mactahoe/logo.png";
    };
    loader.grub = {
      # The reference desktops use systemd-boot; retain this machine's GRUB setup.
      theme = lib.mkDefault "${startup}/share/grub/themes/mactahoe";
      font = lib.mkDefault "${startup}/share/grub/themes/mactahoe/font.pf2";
      # Preserve the existing firmware menu resolution, not desktop modes.
      gfxmodeEfi = lib.mkDefault "1024x768,auto";
      gfxmodeBios = lib.mkDefault "1024x768";
    };
  };
  assertions = [
    {
      assertion = config.boot.loader.timeout != null && config.boot.loader.timeout >= 5;
      message = "MacTahoe must leave at least five seconds to select diagnostics or an older generation.";
    }
  ];
}
