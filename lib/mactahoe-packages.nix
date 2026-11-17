{
  pkgs,
  gtkSource,
  iconsSource,
}:
let
  inherit (pkgs) lib;
  version = source: source.shortRev or "source";
  themeMeta = homepage: description: license: {
    inherit homepage description license;
    platforms = lib.platforms.linux;
  };
  # Upstream detects the compilation target via `gnome-shell --version`.
  # Do not start a real shell or fall back to its hardcoded GNOME 48 target.
  shellVersion = pkgs.writeShellScriptBin "gnome-shell" ''
    printf 'GNOME Shell %s\n' ${lib.escapeShellArg pkgs.gnome-shell.version}
  '';
in
rec {
  gtk = gtkFor false;
  gtkVisual = gtkFor true;
  gtkFor =
    visual:
    (pkgs.whitesur-gtk-theme.override {
      altVariants = [ "normal" ];
      colorVariants = [
        "light"
        "dark"
      ];
      opacityVariants = [ "solid" ];
      themeVariants = [ "default" ];
      schemeVariants = [ "standard" ];
      iconVariant = "apple";
    }).overrideAttrs
      (old: {
        pname = "mactahoe-gtk-theme${lib.optionalString visual "-visual"}";
        version = version gtkSource;
        src = gtkSource;
        patches = [ ];
        postPatch = "";
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.getent
          pkgs.sudo
          pkgs.procps
          shellVersion
        ];
        installPhase = ''
          runHook preInstall
          export HOME="$TMPDIR/home" TERM=xterm USER="$(id -un)"
          mkdir -p "$HOME" "$out/share/themes"
          bash ./install.sh --dest "$out/share/themes" \
            --alt normal --color light --color dark \
            ${if visual then "--opacity normal --blur --name MacTahoe-Visual" else "--opacity solid"} \
            --theme default --scheme standard --gnome-shell -i apple
          install -Dm644 COPYING "$out/share/doc/$pname/COPYING"
          runHook postInstall
        '';
        passthru = {
          gnomeShellVersion = pkgs.gnome-shell.version;
        };
        meta = themeMeta "https://github.com/vinceliuice/MacTahoe-gtk-theme" "MacTahoe ${
          if visual then "upstream blur" else "solid"
        } GTK 3/4 and GNOME Shell themes" lib.licenses.mit;
      });

  icons = (pkgs.whitesur-icon-theme.override { themeVariants = [ "default" ]; }).overrideAttrs (_: {
    pname = "mactahoe-icon-theme";
    version = version iconsSource;
    src = iconsSource;
    patches = [ ];
    postPatch = "";
    installPhase = ''
      runHook preInstall
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME" "$out/share/icons"
      bash ./install.sh --dest "$out/share/icons" --name MacTahoe --theme default
      runHook postInstall
    '';
    # Preserve upstream files and links, including combined icon/cursor themes.
    postFixup = "";
    meta =
      themeMeta "https://github.com/vinceliuice/MacTahoe-icon-theme"
        "MacTahoe light and dark icons with upstream combined cursor assets"
        lib.licenses.gpl3Plus;
  });

  cursors = pkgs.stdenvNoCC.mkDerivation {
    pname = "mactahoe-cursors";
    version = version iconsSource;
    src = iconsSource;
    dontConfigure = true;
    dontBuild = true;
    dontRewriteSymlinks = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/icons/MacTahoe-cursors" "$out/share/icons/MacTahoe-dark-cursors"
      cp -a cursors/dist/. "$out/share/icons/MacTahoe-cursors/"
      cp -a cursors/dist-dark/. "$out/share/icons/MacTahoe-dark-cursors/"
      install -Dm644 cursors/LICENSE "$out/share/doc/$pname/LICENSE"
      runHook postInstall
    '';
    meta =
      themeMeta "https://github.com/vinceliuice/MacTahoe-icon-theme/tree/main/cursors"
        "Upstream precompiled MacTahoe light and dark X cursors"
        lib.licenses.gpl3Only;
  };

  wallpaper = pkgs.stdenvNoCC.mkDerivation {
    pname = "mactahoe-wallpaper";
    version = version gtkSource;
    src = gtkSource;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/wallpapers/MacTahoe"
      cp -a wallpaper/MacTahoe-{day,night}.jpeg "$out/share/wallpapers/MacTahoe/"
      install -Dm644 COPYING "$out/share/doc/$pname/COPYING"
      runHook postInstall
    '';
    meta =
      themeMeta "https://github.com/vinceliuice/MacTahoe-gtk-theme/tree/main/wallpaper"
        "MacTahoe day and night wallpapers"
        lib.licenses.mit;
  };

  firefox = pkgs.stdenvNoCC.mkDerivation {
    pname = "mactahoe-firefox-assets";
    version = version gtkSource;
    src = gtkSource;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/mactahoe/firefox"
      cp -a other/firefox/. "$out/share/mactahoe/firefox/"
      install -Dm644 COPYING "$out/share/doc/$pname/COPYING"
      runHook postInstall
    '';
    meta =
      themeMeta "https://github.com/vinceliuice/MacTahoe-gtk-theme/tree/main/other/firefox"
        "Unmodified MacTahoe Firefox CSS and its relative import tree"
        lib.licenses.mit;
  };

  # The host-oriented tweaks.sh is never run. Keep current GNOME resources and
  # assemble upstream's already resource-relative GDM CSS without rewriting it.
  # Consumers overriding gnome-shell must pass the unthemed package here to avoid
  # a recursive dependency: gdmResourceFor prev.gnome-shell.
  gdmTheme = gdmResourceFor pkgs.gnome-shell;
  gdmResourceFor =
    shellPackage:
    pkgs.runCommand "mactahoe-gdm-theme-${version gtkSource}"
      {
        nativeBuildInputs = [ pkgs.glib ];
        passthru = { inherit shellPackage; };
        meta =
          themeMeta "https://github.com/vinceliuice/MacTahoe-gtk-theme/tree/main/other/gdm"
            "MacTahoe GDM resource preserving the current GNOME resource inventory"
            lib.licenses.mit;
      }
      ''
        stock=${shellPackage}/share/gnome-shell/gnome-shell-theme.gresource
        mkdir -p resources "$out/share/gnome-shell"
        gresource list "$stock" > stock-resources
        while IFS= read -r resource; do
          target="resources$resource"
          mkdir -p "$(dirname "$target")"
          gresource extract "$stock" "$resource" > "$target"
        done < stock-resources
        theme=resources/org/gnome/shell/theme
        mkdir -p "$theme"
        cp -a ${gtkSource}/other/gdm/theme/. "$theme/"
        chmod -R u+w resources
        cp "$theme/gnome-shell-dark.css" "$theme/gdm.css"
        cp "$theme/gnome-shell-dark.css" "$theme/gdm3.css"
        printf '<gresources><gresource prefix="/">\n' > theme.gresource.xml
        while IFS= read -r file; do
          printf '<file>%s</file>\n' "$file" >> theme.gresource.xml
        done < <(find resources -type f -printf '%P\n' | LC_ALL=C sort)
        printf '</gresource></gresources>\n' >> theme.gresource.xml
        glib-compile-resources --sourcedir=resources \
          --target="$out/share/gnome-shell/gnome-shell-theme.gresource" theme.gresource.xml
        install -Dm644 ${gtkSource}/COPYING "$out/share/doc/mactahoe-gdm-theme/COPYING"
      '';
}
