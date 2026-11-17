{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.mactahoe.appearance;
  theme = pkgs.mactahoe;
  variant =
    effects: appearance:
    let
      dark = appearance == "dark";
      shade = if dark then "Dark" else "Light";
      gtk = if effects == "visual" then theme.gtkVisual else theme.gtk;
      gtkTheme = if effects == "visual" then "MacTahoe-Visual-${shade}" else "MacTahoe-${shade}-solid";
      iconTheme = "MacTahoe-${appearance}";
      cursorTheme = if dark then "MacTahoe-dark-cursors" else "MacTahoe-cursors";
    in
    {
      inherit
        gtkTheme
        iconTheme
        cursorTheme
        ;
      gtk3 = "${gtk}/share/themes/${gtkTheme}/gtk-3.0/gtk.css";
      gtk4 = "${gtk}/share/themes/${gtkTheme}/gtk-4.0/gtk.css";
      # GTK resolves relative assets against the import URI, not necessarily a
      # symlink's canonical target. This Store wrapper gives them a Store base.
      gtk4Leaf = pkgs.writeText "mactahoe-${effects}-${appearance}-gtk4.css" ''
        @import url("${gtk}/share/themes/${gtkTheme}/gtk-4.0/gtk.css");
      '';
      shell = "${gtk}/share/themes/${gtkTheme}/gnome-shell/gnome-shell.css";
      icons = "${theme.icons}/share/icons/${iconTheme}/index.theme";
      cursor = "${theme.cursors}/share/icons/${cursorTheme}/index.theme";
      wallpaper = "${theme.wallpaper}/share/wallpapers/MacTahoe/MacTahoe-${
        if dark then "night" else "day"
      }.jpeg";
    };
  extension =
    entry:
    let
      root = "${entry.package}/share/gnome-shell/extensions/${entry.package.extensionUuid}";
    in
    {
      inherit (entry) role;
      uuid = entry.package.extensionUuid;
      metadata = "${root}/metadata.json";
      schemaDir = "${root}/schemas";
      schemas = entry.schemas or [ ];
    };
  manifest = pkgs.writeText "mactahoe-appearance.json" (
    builtins.toJSON {
      variants = lib.genAttrs [ "visual" "compatible" ] (
        effects: lib.genAttrs [ "light" "dark" ] (variant effects)
      );
      gnomeMajor = lib.versions.major pkgs.gnome-shell.version;
      flatpakSystemOverride = "/var/lib/flatpak/overrides/global";
      extensions = map extension (
        cfg.extensions
        ++ map (package: {
          inherit package;
          role = "functional-${package.extensionUuid}";
        }) cfg.functionalExtensions
      );
      conflictingExtensions = [
        "rounded-window-corners@fxgn"
      ];
      # Upstream names the conflict without a UUID. Resolve only this exact
      # metadata name among installed extensions, never guess a UUID or wildcard.
      conflictingExtensionNames = [ "Desaturate Windows" ];
      commands = {
        busctl = "${pkgs.systemd}/bin/busctl";
        systemctl = "${pkgs.systemd}/bin/systemctl";
        gsettings = "${pkgs.glib}/bin/gsettings";
        dconf = "${pkgs.dconf}/bin/dconf";
        flatpak = "${pkgs.flatpak}/bin/flatpak";
      };
    }
  );
  runtime = pkgs.writeShellScriptBin "mactahoe-appearance" ''
    export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gnome-shell}/share/gsettings-schemas/${pkgs.gnome-shell.name}:${theme.icons}/share:${theme.cursors}/share:${theme.gtk}/share:${theme.gtkVisual}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
    exec ${pkgs.python3}/bin/python3 -B ${./appearance.py} --manifest ${manifest} "$@"
  '';
in
{
  options.mactahoe.appearance = {
    functionalExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Installed functional extensions seeded without overriding user disables.";
    };
    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "MacTahoe-managed extension packages, roles and schema IDs.";
    };
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      readOnly = true;
    };
    manifest = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      readOnly = true;
    };
  };
  config = lib.mkIf (lib.attrByPath [ "desktop" "gnome" "enable" ] false osConfig) {
    mactahoe.appearance = {
      package = runtime;
      inherit manifest;
    };
    home.packages = [ runtime ];
    home.activation.mactahoeAppearance =
      lib.hm.dag.entryAfter
        [
          "linkGeneration"
          "dconfSettings"
        ]
        ''
          # Do not block Home Manager or login when a compositor capability is absent.
          if ! run ${runtime}/bin/mactahoe-appearance --restore-session apply; then
            echo "MacTahoe appearance was not applied; preferences retained. See the error above." >&2
          fi
        '';
    xdg.configFile."autostart/mactahoe-appearance.desktop".text = ''
      [Desktop Entry]
      Name=Restore MacTahoe appearance
      Exec=${runtime}/bin/mactahoe-appearance apply
      Type=Application
      OnlyShowIn=GNOME;
      X-GNOME-Autostart-Phase=Applications
      X-systemd-skip=false
    '';
    xdg.desktopEntries = lib.listToAttrs (
      map
        (
          entry:
          lib.nameValuePair "mactahoe-${entry.id}" {
            inherit (entry) name;
            exec = "${runtime}/bin/mactahoe-appearance ${entry.command}";
            icon = "preferences-desktop-theme";
            categories = [
              "Settings"
              "DesktopSettings"
            ];
            terminal = false;
          }
        )
        [
          {
            id = "light";
            name = "MacTahoe Light";
            command = "light";
          }
          {
            id = "dark";
            name = "MacTahoe Dark";
            command = "dark";
          }
          {
            id = "toggle";
            name = "Toggle MacTahoe Light / Dark";
            command = "toggle";
          }
          {
            id = "visual";
            name = "MacTahoe Visual Effects";
            command = "effects visual";
          }
          {
            id = "compatible";
            name = "MacTahoe Tray Compatibility";
            command = "effects compatible";
          }
        ]
    );
  };
}
