{ configurations, lib }:
let
  assertChecks =
    name: checks:
    assert lib.assertMsg (lib.all (value: value) (
      builtins.attrValues checks
    )) "${name}: ${builtins.toJSON checks}";
    checks;
  directories =
    entries: map (entry: if builtins.isAttrs entry then entry.directory else entry) entries;
  isShellSetting =
    path:
    lib.any (prefix: path == prefix || lib.hasPrefix "${prefix}/" path) [
      "org/gnome/shell"
      "org/gnome/mutter"
      "org/gnome/settings-daemon"
    ];
  checkHost =
    name:
    let
      host = configurations.${name};
      cfg = host.config;
      home = cfg.home-manager.users.tippy;
      umbriel = home.programs.umbriel.settings;
      noctalia = home.programs.noctalia.settings;
      service = cfg.systemd.user.services.noctalia;
      persisted = directories home.home.global-persistence.directories;
      homePackages = map lib.getName home.home.packages;
      diagnostic = cfg.specialisation.no-animation-diagnostic.configuration;
      originalPlymouth =
        (host.extendModules { modules = [ { boot.plymouth.theme = "mactahoe"; } ]; }).config;
      override =
        (host.extendModules {
          modules = [ { home-manager.users.tippy.programs.noctalia.settings.theme.mode = "dark"; } ];
        }).config.home-manager.users.tippy;
      autostartFiles = lib.filterAttrs (
        path: entry: lib.hasPrefix "autostart/" path && entry.enable
      ) home.xdg.configFile;
    in
    {
      default = assertChecks "${name}/umbriel" {
        newDefault =
          cfg.desktop.defaultSession == "umbriel"
          && cfg.services.displayManager.defaultSession == "umbriel"
          && cfg.desktop.umbriel.enable
          && cfg.desktop.noctalia.enable
          && cfg.programs.umbriel.enable
          && cfg.programs.noctalia.enable
          && home.programs.umbriel.enable
          && home.programs.noctalia.enable
          && home.programs.umbriel.package == cfg.programs.umbriel.package
          && home.programs.noctalia.package == cfg.programs.noctalia.package;
        noPlasmaEnabled =
          !cfg.services.desktopManager.plasma6.enable
          && !(home.programs ? plasma)
          && !(home.xdg.configFile ? "autostart/plasma-manager-autostart.desktop")
          && !(home.xdg.configFile ? "plasma-workspace/env/mactahoe-paths.sh");
        gnomeRetired =
          !cfg.desktop.gnome.enable
          && !cfg.services.desktopManager.gnome.enable
          && !cfg.services.xrdp.enable
          && !(home.home.file ? "startwm.sh")
          && !(home.home.file ? ".config/gnome-initial-setup-done")
          && !(home.home.activation ? allowGdmReadFace)
          && !(lib.any isShellSetting (builtins.attrNames home.dconf.settings))
          && !(lib.any (package: lib.hasPrefix "gnome-shell-extension" package) homePackages)
          && !(cfg.xdg.portal.config ? gnome);
        onePasswordGreeter =
          cfg.desktop.loginManager == "noctalia"
          && cfg.services.displayManager.noctalia-greeter.enable
          && cfg.services.greetd.enable
          && !cfg.services.displayManager.sddm.enable
          && !cfg.services.displayManager.gdm.enable
          && !cfg.services.displayManager.autoLogin.enable
          && !(cfg.services.greetd.settings ? initial_session)
          && cfg.services.displayManager.noctalia-greeter.settings.session.default == "umbriel"
          && lib.elem cfg.programs.umbriel.package cfg.services.displayManager.sessionPackages;
        passwordKeyring =
          cfg.services.gnome.gnome-keyring.enable
          && cfg.security.pam.services.greetd.rules.auth.login.modulePath == "login"
          && cfg.security.pam.services.greetd.rules.session.login.modulePath == "login"
          && cfg.security.pam.services.login.enableGnomeKeyring
          && cfg.security.pam.services.login.rules.auth.gnome_keyring.enable
          && cfg.security.pam.services.login.rules.session.gnome_keyring.enable
          && lib.elem "seahorse" homePackages
          && lib.hasInfix "gnome-keyring" (
            toString home.xdg.dataFile."dbus-1/services/org.freedesktop.secrets.service".source
          );
        nativePortalRouting =
          cfg.xdg.portal.enable
          && lib.elem cfg.programs.umbriel.portalPackage cfg.xdg.portal.extraPortals
          && cfg.xdg.portal.config.umbriel.default == "umbriel;gtk"
          && cfg.xdg.portal.config.umbriel."org.freedesktop.impl.portal.ScreenCast" == "umbriel"
          && cfg.xdg.portal.config.umbriel."org.freedesktop.impl.portal.Screenshot" == "umbriel"
          && cfg.xdg.portal.config.umbriel."org.freedesktop.impl.portal.FileChooser" == "gtk"
          && cfg.xdg.portal.config.umbriel."org.freedesktop.impl.portal.Secret" == "gnome-keyring";
        noKdePortal =
          !(cfg.xdg.portal.config ? kde)
          && !(lib.any (
            package: lib.getName package == "xdg-desktop-portal-kde"
          ) cfg.xdg.portal.extraPortals);
        nativeSessionService =
          lib.elem cfg.programs.umbriel.package cfg.systemd.packages
          && cfg.programs.noctalia.systemd.enable
          && cfg.programs.noctalia.systemd.target == "umbriel-session.target"
          && service.partOf == [ "umbriel-session.target" ]
          && service.after == [ "umbriel-session.target" ]
          && service.wantedBy == [ "umbriel-session.target" ]
          && service.serviceConfig.Type == "notify"
          && service.before == [ "xdg-desktop-autostart.target" ]
          && service.serviceConfig.ExecStart == "${cfg.programs.noctalia.package}/bin/noctalia";
        noDuplicateShell =
          !home.programs.noctalia.systemd.enable
          && !(home.systemd.user.services ? noctalia)
          && !(lib.any (command: lib.hasInfix "noctalia" command) (umbriel.general.autostart or [ ]))
          && lib.all (
            path:
            !(lib.hasInfix "noctalia" (
              lib.toLower "${path}\n${
                if autostartFiles.${path}.text == null then "" else autostartFiles.${path}.text
              }"
            ))
          ) (builtins.attrNames autostartFiles);
        nativeDesktopServices =
          home.window-manager.enable
          && cfg.security.polkit.enable
          && noctalia.shell.polkit_agent
          && noctalia.shell.clipboard_enabled
          && noctalia.notification.enable_daemon
          && noctalia.lockscreen.enabled
          && !noctalia.lockscreen.allow_empty_password
          && !(home.systemd.user.services ? window-manager-polkit)
          && !(home.systemd.user.services ? polkit-gnome)
          && !(home.services.cliphist.enable or false)
          && !(home.services.dunst.enable or false)
          && !(home.services.mako.enable or false)
          && !(lib.any (command: lib.hasInfix "wl-paste" command || lib.hasInfix "cliphist" command) (
            umbriel.general.autostart or [ ]
          ))
          && lib.all (package: lib.elem package homePackages) [
            "wl-clipboard"
            "cliphist"
            "grim"
            "slurp"
            "satty"
          ];
        upstreamCompositorPackage =
          !(cfg.programs.umbriel.package.genericAuxiliaryPlacement or false)
          && lib.all (patch: !(lib.hasSuffix "umbriel-auxiliary-windows.patch" (toString patch))) (
            cfg.programs.umbriel.package.patches or [ ]
          )
          && home.programs.umbriel.package.outPath == cfg.programs.umbriel.package.outPath
          && !cfg.systemd.user.services.umbriel.restartIfChanged;
        desktopDependencies =
          cfg.networking.networkmanager.enable
          && cfg.hardware.bluetooth.enable
          && cfg.services.upower.enable
          && cfg.security.rtkit.enable
          && cfg.services.pipewire.enable
          && cfg.services.pipewire.audio.enable
          && cfg.services.pipewire.pulse.enable
          && cfg.services.pipewire.wireplumber.enable;
        nativeFcitx =
          cfg.desktop.inputMethod.framework == "fcitx5"
          && cfg.i18n.inputMethod.enable
          && cfg.i18n.inputMethod.type == "fcitx5"
          && cfg.i18n.inputMethod.fcitx5.waylandFrontend
          && cfg.environment.variables.XMODIFIERS == "@im=fcitx"
          && home.home.sessionVariables.QT_IM_MODULE == "fcitx"
          && lib.hasInfix "Font=Sans 10" home.xdg.configFile."fcitx5/conf/classicui.conf".text
          && lib.hasInfix "EnableFractionalScale=True" home.xdg.configFile."fcitx5/conf/classicui.conf".text
          && !(home.xdg.configFile ? "ibus/rime")
          && !(home.xdg.desktopEntries ? plasma-ibus-wayland)
          && !(home.systemd.user.services ? "org.freedesktop.IBus.session.GNOME")
          && home.xdg.dataFile."fcitx5/rime".recursive
          && lib.hasInfix (builtins.unsafeDiscardStringContext "${cfg.i18n.inputMethod.package}/bin/fcitx5") (
            toString umbriel.general.autostart
          );
        persistentDesktopState =
          cfg.environment.global-persistence.enable
          && home.home.global-persistence.enabled
          && lib.all (path: lib.elem path persisted) [
            ".config/noctalia"
            ".local/state/noctalia"
            ".local/share/noctalia"
            ".config/umbriel"
            ".local/share/fcitx5"
            ".local/share/keyrings"
          ]
          && lib.elem "/var/lib/noctalia-greeter" (
            directories cfg.environment.global-persistence.directories
          );
        persistentDesktopLogs =
          cfg.services.journald.settings.Journal.Storage == "persistent"
          && lib.elem "/var/log/journal" (directories cfg.environment.global-persistence.directories);
        declaredStartup =
          cfg.boot.plymouth.enable
          && cfg.boot.plymouth.theme == "bgrt"
          && lib.hasSuffix "/IosevkaTermSlabNerdFontMono-Regular.ttf" cfg.boot.plymouth.font
          && !(lib.elem cfg.desktop.mactahoe.startupPackage cfg.boot.plymouth.themePackages)
          &&
            cfg.boot.loader.grub.theme == "${cfg.desktop.mactahoe.startupPackage}/share/grub/themes/mactahoe";
        originalAnimationAvailable =
          originalPlymouth.boot.plymouth.theme == "mactahoe"
          && lib.elem cfg.desktop.mactahoe.startupPackage originalPlymouth.boot.plymouth.themePackages
          &&
            originalPlymouth.boot.plymouth.logo
            == "${cfg.desktop.mactahoe.startupPackage}/share/plymouth/themes/mactahoe/logo.png";
        diagnosticBoot =
          !diagnostic.boot.plymouth.enable
          && lib.elem "panic=0" diagnostic.boot.kernelParams
          && lib.elem "loglevel=7" diagnostic.boot.kernelParams
          && !(lib.elem "panic=1" diagnostic.boot.kernelParams)
          && !(lib.elem "quiet" diagnostic.boot.kernelParams)
          && !(lib.elem "splash" diagnostic.boot.kernelParams)
          && builtins.attrNames diagnostic.specialisation == [ ]
          && diagnostic.boot.loader.grub.extraEntries == cfg.boot.loader.grub.extraEntries
          && lib.all (param: lib.elem param diagnostic.boot.kernelParams) (
            lib.filter (
              param:
              !(lib.elem (builtins.head (lib.splitString "=" param)) [
                "quiet"
                "splash"
                "loglevel"
                "panic"
                "plymouth.enable"
                "systemd.show_status"
                "rd.systemd.show_status"
              ])
            ) cfg.boot.kernelParams
          );
        rollbackRetained =
          cfg.boot.loader.timeout >= 5
          && !cfg.nix.gc.automatic
          && cfg.boot.loader.grub.configurationLimit >= 2
          && lib.hasInfix "Windows" cfg.boot.loader.grub.extraEntries
          && lib.hasInfix "bootmgfw.efi" cfg.boot.loader.grub.extraEntries;
        layeredShellSettings =
          home.programs.noctalia.checkConfig
          && home.xdg.configFile."noctalia/config.toml".enable
          && !(home.home.file ? ".local/state/noctalia/settings.toml")
          && override.programs.noctalia.settings.theme.mode == "dark"
          && override.programs.noctalia.settings.shell.polkit_agent;
        segmentedBar =
          let
            bar = noctalia.bar.main;
          in
          bar.background_opacity == 0
          && bar.border_width == 0
          && !bar.compositor_blur
          && bar.capsule_opacity == 0.60
          && !bar.shadow
          && !bar.contact_shadow
          && bar.dead_zone.click_through
          &&
            bar.start == [
              "group:workspaces"
              "group:resources"
              "group:visualizer"
            ]
          && bar.center == [ "group:clock" ]
          &&
            bar.end == [
              "group:tray"
              "group:controls"
            ]
          &&
            map (group: group.id) bar.capsule_group == [
              "workspaces"
              "resources"
              "visualizer"
              "clock"
              "tray"
              "controls"
            ]
          && lib.all (group: group.members != [ ] && group.opacity == 0.60) bar.capsule_group
          &&
            (builtins.elemAt bar.capsule_group 1).members == [
              "cpu"
              "ram"
              "temperature"
            ]
          && (builtins.elemAt bar.capsule_group 3).members == [ "clock" ]
          && !(lib.elem "control-center" (builtins.elemAt bar.capsule_group 5).members)
          && bar.capsule_radius == 17.0
          && bar.scale == 1.0
          && noctalia.widget.workspaces.pill_scale == 1.0
          &&
            lib.all
              (
                widget:
                widget.visualization == "gauge" && !widget.show_value && widget.show_glyph && widget.scale == 1.0
              )
              [
                noctalia.widget.cpu
                noctalia.widget.ram
                noctalia.widget.temperature
              ]
          && noctalia.widget.audio-visualizer.type == "audio_visualizer"
          && noctalia.widget.audio-visualizer.show_when_idle;
        fullVerticalArea = !noctalia.dock.enabled && umbriel.layout.gap == 0;
        frostedLayers =
          umbriel.appearance.blur.enabled
          && umbriel.appearance.blur.radius == 10
          && lib.any (
            rule: (rule.blur or false) && (rule.blur_ignore_alpha or 1.0) == 0.05
          ) umbriel.layer_rule
          && lib.any (rule: !(rule.blur_optimized or true)) umbriel.layer_rule;
        barAlphaMaskedBlur = lib.any (
          rule:
          (rule.match.namespace or "") == "^noctalia-bar-main$"
          && (rule.blur or false)
          && (rule.blur_ignore_alpha or 1.0) == 0.05
          && !(rule.blur_optimized or true)
        ) umbriel.layer_rule;
        kittyGlass =
          let
            rule = lib.findFirst (rule: (rule.match.app_id or "") == "^kitty$") null umbriel.window_rule;
          in
          rule != null
          && rule.border_width == 0
          && rule.outer_border_width == 0
          && rule.border_effect == "off"
          && rule.blur
          && !rule.blur_optimized
          && (rule.corner_radius or umbriel.appearance.corner_radius) == 12
          && home.programs.kitty.settings.background_opacity == 0.80
          && home.programs.kitty.settings.dynamic_background_opacity
          && home.programs.kitty.settings.transparent_background_colors == "#282a36"
          && home.programs.kitty.settings.window_border_width == 0
          && home.programs.kitty.settings.window_margin_width == 0
          && home.programs.kitty.settings.window_padding_width == 0;
        wpsUsesGlobalScale =
          lib.hasSuffix "-configured" host.pkgs.wpsoffice-cn.name
          && !(lib.hasInfix "--set QT_AUTO_SCREEN_SCALE_FACTOR" host.pkgs.wpsoffice-cn.buildCommand)
          && !(lib.hasInfix "--set QT_ENABLE_HIGHDPI_SCALING" host.pkgs.wpsoffice-cn.buildCommand)
          && !(lib.hasInfix "--set QT_SCALE_FACTOR" host.pkgs.wpsoffice-cn.buildCommand);
        applicationScaling =
          home.programs.alacritty.settings.font.size == 15
          && !(lib.any (package: lib.getName package == "steam-hidpi") cfg.environment.systemPackages)
          && !(lib.any (
            package: lib.getName package == "bottles-gnome-auto-dpi"
          ) cfg.environment.systemPackages);
        lightShell = noctalia.theme.mode == "light" && noctalia.theme.shell_mode == "light";
        frostedLockscreen =
          noctalia.shell.panel.transparency_mode == "soft"
          && noctalia.lockscreen.blur_intensity == 0.75
          && !noctalia.lockscreen.blurred_desktop
          && noctalia.lockscreen_widgets.enabled
          && noctalia.lockscreen_widgets.widget.lock-cpu.settings.stat == "cpu_usage"
          && noctalia.lockscreen_widgets.widget.lock-cpu.settings.stat2 == "cpu_temp"
          && noctalia.lockscreen_widgets.widget.lock-network.settings.stat == "net_rx"
          && noctalia.lockscreen_widgets.widget.lock-network.settings.stat2 == "net_tx"
          && noctalia.lockscreen_widgets.widget.lock-ram.settings.stat == "ram_pct"
          && noctalia.lockscreen_widgets.widget.lock-calendar.type == "calendar"
          && (
            if name == "arx8" then
              let
                login = noctalia.lockscreen_widgets.widget."lockscreen-login-box@eDP-1";
              in
              login.output == "eDP-1"
              && login.cx == noctalia.lockscreen_widgets.widget.lock-clock.cx
              && login.cy > noctalia.lockscreen_widgets.widget.lock-clock.cy
              && login.box_width > 0
              && login.box_height > 0
              && login.settings.layout == "compact"
              && !login.settings.show_login_button
              && !login.settings.show_password_reveal
              && !login.settings.show_session_buttons
            else
              true
          );
        independentPopupBackground =
          noctalia.shell.panel.transparency_mode == "soft"
          && noctalia.shell.panel.control_center_placement == "floating"
          && noctalia.shell.panel.session_placement == "floating"
          && noctalia.shell.panel.wallpaper_placement == "floating"
          && noctalia.shell.panel.open_near_click_control_center
          && noctalia.shell.panel.open_near_click_session
          && noctalia.shell.panel.open_near_click_wallpaper;
        rectangularLockscreen =
          name != "arx8"
          || (
            let
              widgets = noctalia.lockscreen_widgets.widget;
              top = widget: widget.cy - widget.box_height / 2;
              bottom = widget: widget.cy + widget.box_height / 2;
              left = widget: widget.cx - widget.box_width / 2;
              right = widget: widget.cx + widget.box_width / 2;
              login = widgets."lockscreen-login-box@eDP-1";
            in
            top widgets.lock-cpu == top widgets.lock-clock
            && top widgets.lock-calendar == top widgets.lock-clock
            && bottom widgets.lock-ram == bottom widgets.lock-clock
            && bottom widgets.lock-calendar == bottom widgets.lock-clock
            && top widgets.lock-network - bottom widgets.lock-cpu == 24
            && top widgets.lock-ram - bottom widgets.lock-network == 24
            && left widgets.lock-clock - right widgets.lock-cpu == 32
            && left widgets.lock-calendar - right widgets.lock-clock == 32
            && left login - left widgets.lock-clock == 32
            && right widgets.lock-clock - right login == 32
            && bottom widgets.lock-clock - bottom login == 32
            && login.settings.background_opacity == 0.0
          );
        desktopCards =
          noctalia.desktop_widgets.enabled
          &&
            noctalia.desktop_widgets.widget_order == [
              "clock-card"
              "weather-card"
              "monitor-network"
              "monitor-cpu"
              "monitor-gpu"
              "monitor-memory"
              "monitor-vram"
            ]
          && noctalia.desktop_widgets.widget.clock-card.type == "clock"
          && noctalia.desktop_widgets.widget.weather-card.type == "weather"
          && noctalia.desktop_widgets.widget.monitor-cpu.type == "local/sysmon-cards:card"
          && lib.all (
            widget: widget.placement_width == 1707.0 && widget.placement_height == 1067.0 && widget.cx == 1547.0
          ) (builtins.attrValues noctalia.desktop_widgets.widget)
          && noctalia.desktop_widgets.widget.clock-card.cy == 128.0
          && noctalia.desktop_widgets.widget.weather-card.cy == 244.0
          && noctalia.desktop_widgets.widget.monitor-network.cy == 368.0
          && noctalia.location.auto_locate
          && noctalia.weather.enabled
          && noctalia.weather.unit == "metric";
        allDesktopSystemStats =
          let
            desktop = noctalia.desktop_widgets;
            widgets = map (id: desktop.widget.${id}) desktop.widget_order;
            monitors = lib.filter (widget: widget.type == "local/sysmon-cards:card") widgets;
            top = widget: widget.cy - widget.box_height / 2;
            bottom = widget: widget.cy + widget.box_height / 2;
            previous = lib.take (builtins.length widgets - 1) widgets;
            next = lib.drop 1 widgets;
          in
          builtins.length monitors == 5
          &&
            map (widget: widget.settings.group) monitors == [
              "network"
              "cpu"
              "gpu"
              "memory"
              "vram"
            ]
          && lib.all (widget: widget.box_width == 256.0 && widget.settings.background_padding == 8.0) monitors
          && lib.all (
            widget:
            widget.box_height == (
              if
                lib.elem widget.settings.group [
                  "cpu"
                  "gpu"
                ]
              then
                152.0
              else
                112.0
            )
          ) monitors
          && lib.all (widget: top widget >= 44 && bottom widget <= widget.placement_height) widgets
          && lib.all (gap: gap == 12.0) (lib.zipListsWith (a: b: top b - bottom a) previous next)
          && lib.elem "local/sysmon-cards" noctalia.plugins.enabled
          && noctalia.desktop_widgets.widget.monitor-gpu.settings.gpu_frequency_command != [ ]
          && noctalia.system.monitor.enabled;
        originalWallpaper =
          noctalia.wallpaper.default.path == "${host.pkgs.wallpaper}/wallpaper.jpg"
          &&
            cfg.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path
            == noctalia.wallpaper.default.path;
        hdrWallpaper =
          if name == "arx8" then
            noctalia.wallpaper.enabled
            &&
              home.systemd.user.services.hdr-wallpaper.Service.ExecStart == [
                "${host.pkgs.hdr-wallpaper}/bin/hdr-wallpaper eDP-1 ${host.pkgs.wallpaper.hdr}/wallpaper-hdr.png"
              ]
            && home.systemd.user.services.hdr-wallpaper.Service.Type == "notify"
            &&
              home.systemd.user.services.hdr-wallpaper.Service.ExecStartPost
              == "${cfg.programs.noctalia.package}/bin/noctalia msg config-set wallpaper.enabled false"
            &&
              home.systemd.user.services.hdr-wallpaper.Service.ExecStopPost
              == "-${cfg.programs.noctalia.package}/bin/noctalia msg config-set wallpaper.enabled true"
            && lib.elem "noctalia.service" home.systemd.user.services.hdr-wallpaper.Unit.After
            && lib.elem "umbriel-session.target" home.systemd.user.services.hdr-wallpaper.Unit.After
            && home.systemd.user.services.hdr-wallpaper.Install.WantedBy == [ "umbriel-session.target" ]
          else
            noctalia.wallpaper.enabled && !(home.systemd.user.services ? hdr-wallpaper);
        officialGreeterAppearance =
          let
            greeter = cfg.services.displayManager.noctalia-greeter.settings;
          in
          greeter.appearance.scheme == "Noctalia"
          && greeter.appearance.theme_mode == "light"
          && !greeter.appearance.hide_logo
          && greeter.appearance.password_style == "default"
          && greeter.clock.enabled
          && greeter.clock.position == "above-panel"
          && greeter.user.default == "tippy";
        themeOwnership =
          home.gtk.enable
          && home.gtk.theme.name == "MacTahoe-Light-solid"
          && home.gtk.iconTheme.name == "MacTahoe-light"
          && home.home.pointerCursor.name == "MacTahoe-cursors"
          && !home.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme
          && !home.gtk.gtk4.extraConfig.gtk-application-prefer-dark-theme
          && home.dconf.settings."org/gnome/desktop/interface".color-scheme == "prefer-light"
          && noctalia.theme.mode == "light"
          && noctalia.theme.shell_mode == "light"
          &&
            lib.all
              (
                name:
                home.programs.firefox.policies.Preferences.${name} == {
                  Value = 1;
                  Status = "locked";
                }
              )
              [
                "layout.css.prefers-color-scheme.content-override"
                "browser.theme.content-theme"
                "browser.theme.toolbar-theme"
              ]
          && !noctalia.theme.sync_color_scheme
          && !noctalia.theme.templates.enable_builtin_templates
          && noctalia.theme.templates.builtin_ids == [ ]
          && noctalia.theme.templates.user.umbriel.output_path == "$XDG_CONFIG_HOME/umbriel/noctalia.toml"
          && !(noctalia.theme.templates.user.umbriel ? post_hook)
          && !(lib.elem "kitty" noctalia.theme.templates.builtin_ids)
          && noctalia.theme.templates.user.kitty.output_path == "$XDG_STATE_HOME/noctalia/kitty-theme.conf"
          && lib.hasSuffix "-noctalia-kitty-dark.conf" noctalia.theme.templates.user.kitty.input_path
          && lib.hasInfix "kitty-wrapped" noctalia.theme.templates.user.kitty.post_hook
          && lib.hasInfix "include ${home.xdg.stateHome}/noctalia/kitty-theme.conf" home.programs.kitty.extraConfig
          && !(home.home.file ? ".local/state/noctalia/kitty-theme.conf");
        nonblockingShellSwaps = name != "arx8" || service.environment.__GL_SYNC_TO_VBLANK == "0";
        nativeKeybinds =
          !(umbriel ? scratchpad)
          && !(umbriel.keybinds ? Super)
          && !(umbriel.keybinds ? Mod)
          && !(umbriel.keybinds ? "Alt+Tab")
          && !(umbriel.keybinds ? "Mod+Ctrl+Left")
          && umbriel.keybinds."Mod+L" == "window-focus-right"
          && umbriel.keybinds."Mod+H" == "window-focus-left"
          && umbriel.keybinds."Mod+Comma" == "window-consume-left"
          && umbriel.keybinds."Mod+Period" == "window-consume-right"
          && umbriel.keybinds."Mod+Space" == "scratchpad-toggle"
          && umbriel.keybinds."Mod+Escape" == "session-quit"
          && umbriel.keybinds."Mod+O".action == "overview-toggle";
        launcherSearch =
          noctalia.plugins.enabled == [
            "cleboost/ssh-launcher"
            "nightwatch75/file-search"
            "3dprogramin/vscode"
            "local/sysmon-cards"
          ]
          && noctalia.plugins.auto_update == "none"
          && lib.any (source: source.kind == "path" && source.enabled) noctalia.plugins.source
          && !noctalia.plugin_settings."nightwatch75/file-search".space_enabled
          && noctalia.plugin_settings."3dprogramin/vscode".editor == "code"
          && lib.all (name: lib.elem name homePackages) [
            "findutils"
            "fzf"
            "openssh"
            "sqlite"
            "xdg-utils"
          ];
        measuredOutputOnly =
          if name == "arx8" then
            builtins.attrNames umbriel.output == [ "eDP-1" ]
            && umbriel.output."eDP-1".mode == "2560x1600@240"
            && umbriel.output."eDP-1".scale == 1.5
            && umbriel.output."eDP-1".hdr == "on"
            && umbriel.output."eDP-1".workspaces == 4
            && !umbriel.general.xwayland_native_resolution
            && home.wayland.dpi == 96
            && cfg.services.displayManager.noctalia-greeter.settings.output.scales == "eDP-1:1.5"
            && !cfg.services.displayManager.noctalia-greeter.settings.output.use_synced_settings
          else
            (umbriel.output or { }) == { };
        noGlobalScaling =
          !(home.dconf.settings."org/gnome/desktop/interface" ? scaling-factor)
          &&
            lib.all
              (
                variables:
                lib.all (key: !(builtins.hasAttr key variables)) [
                  "GDK_SCALE"
                  "GDK_DPI_SCALE"
                  "QT_SCALE_FACTOR"
                  "QT_SCREEN_SCALE_FACTORS"
                  "QT_WAYLAND_FORCE_DPI"
                  "WLR_NO_HARDWARE_CURSORS"
                ]
              )
              [
                cfg.environment.variables
                cfg.environment.sessionVariables
                home.home.sessionVariables
                umbriel.environment
              ];
      };
      inputFrameworks = lib.genAttrs [ "fcitx5" "ibus" ] (
        framework:
        let
          variant =
            (host.extendModules {
              modules = [ { desktop.inputMethod.framework = lib.mkForce framework; } ];
            }).config;
          variantHome = variant.home-manager.users.tippy;
        in
        assertChecks "${name}/${framework}" {
          desktopUnchanged =
            variant.desktop.defaultSession == "umbriel"
            && variant.programs.umbriel.enable
            && variant.programs.noctalia.enable
            && !variant.services.desktopManager.gnome.enable
            && !variant.services.desktopManager.plasma6.enable
            && !(variantHome.programs ? plasma)
            && variant.services.displayManager.noctalia-greeter.enable;
          frameworkSelected =
            variant.desktop.inputMethod.framework == framework
            && variant.i18n.inputMethod.enable
            && variant.i18n.inputMethod.type == framework;
          frameworkState =
            if framework == "ibus" then
              !variant.i18n.inputMethod.ibus.waylandFrontend
              && variantHome.home.sessionVariables.GTK_IM_MODULE == "ibus"
              && variantHome.home.sessionVariables.QT_IM_MODULE == "ibus"
              && variantHome.xdg.configFile."ibus/rime".recursive
              && toString variantHome.dconf.settings."desktop/ibus/general".preload-engines == "@as ['rime']"
              && !(variantHome.xdg.configFile ? "fcitx5/config")
              && !(variantHome.xdg.dataFile ? "fcitx5/rime")
              && !(variantHome.xdg.configFile ? "autostart/org.fcitx.Fcitx5.desktop")
              && !(variantHome.systemd.user.services ? "org.freedesktop.IBus.session.GNOME")
            else
              variant.i18n.inputMethod.fcitx5.waylandFrontend
              && variantHome.home.sessionVariables.QT_IM_MODULE == "fcitx"
              && variantHome.xdg.dataFile."fcitx5/rime".recursive
              && !(variantHome.xdg.configFile ? "ibus/rime");
        }
      );
      legacy = lib.genAttrs [ "gnome" ] (
        session:
        let
          legacy =
            (host.extendModules {
              modules = [ { desktop.defaultSession = lib.mkForce session; } ];
            }).config;
          legacyHome = legacy.home-manager.users.tippy;
        in
        assertChecks "${name}/${session}" {
          restoredDesktops =
            legacy.desktop.defaultSession == session
            && legacy.services.displayManager.defaultSession == "gnome"
            && legacy.desktop.gnome.enable
            && legacy.services.desktopManager.gnome.enable
            && !legacy.services.desktopManager.plasma6.enable
            && !(legacyHome.programs ? plasma)
            && !legacy.desktop.umbriel.enable
            && !legacy.desktop.noctalia.enable
            && !legacy.programs.umbriel.enable
            && !legacy.programs.noctalia.enable
            && !legacyHome.programs.umbriel.enable
            && !legacyHome.programs.noctalia.enable
            && !legacyHome.window-manager.enable;
          restoredGreeter =
            legacy.desktop.loginManager == "noctalia"
            && !legacy.services.displayManager.sddm.enable
            && !legacy.services.displayManager.gdm.enable
            && legacy.services.greetd.enable
            && legacy.services.displayManager.noctalia-greeter.enable
            && legacy.services.displayManager.noctalia-greeter.settings.session.default == "gnome"
            && !legacy.services.displayManager.autoLogin.enable
            && !(legacy.services.greetd.settings ? initial_session);
          restoredIbus =
            legacy.desktop.inputMethod.framework == "ibus"
            && legacy.i18n.inputMethod.type == "ibus"
            && !legacy.i18n.inputMethod.ibus.waylandFrontend
            && legacyHome.home.sessionVariables.GTK_IM_MODULE == "ibus"
            && legacyHome.home.sessionVariables.QT_IM_MODULE == "ibus"
            && legacyHome.xdg.configFile."ibus/rime".recursive;
          restoredGnomeConfiguration =
            legacy.services.xrdp.enable
            && legacyHome.home.file."startwm.sh".enable
            && legacyHome.dconf.settings ? "org/gnome/shell/extensions/dash-to-dock"
            && legacy.xdg.portal.config.gnome.default == "gnome;gtk";
          noKdePortal =
            !(legacy.xdg.portal.config ? kde)
            && !(lib.any (
              package: lib.getName package == "xdg-desktop-portal-kde"
            ) legacy.xdg.portal.extraPortals);
        }
      );
    };
in
lib.genAttrs [ "arx8" "surface" ] checkHost
