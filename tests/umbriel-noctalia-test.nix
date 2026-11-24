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
  near = a: b: a - b > -0.001 && a - b < 0.001;
  orderedWidgets = section: map (id: section.widget.${id}) section.widget_order;
  validOrder =
    section:
    section.widget_order != [ ]
    && lib.unique section.widget_order == section.widget_order
    && lib.all (id: builtins.hasAttr id section.widget) section.widget_order;
  inside =
    width: height: widget:
    widget.cx - widget.box_width / 2 >= -0.001
    && widget.cy - widget.box_height / 2 >= -0.001
    && widget.cx + widget.box_width / 2 <= width + 0.001
    && widget.cy + widget.box_height / 2 <= height + 0.001;
  # The pinned PlacementMapper changes centres independently on each axis. It
  # leaves box sizes alone; this model does not execute the renderer or its clamp.
  remap =
    width: height: widget:
    widget
    // {
      cx = widget.cx * width / widget.placement_width;
      cy = widget.cy * height / widget.placement_height;
      placement_width = width;
      placement_height = height;
    };
  safeShowcaseValue =
    gpuFrequencyCommand: value:
    let
      check =
        path: value:
        if builtins.isAttrs value then
          lib.all (
            key:
            (
              builtins.match ".*(command|exec|script).*" key == null
              || (
                path == [
                  "showcase-processors"
                  "settings"
                ]
                && key == "gpu_frequency_command"
                && gpuFrequencyCommand != [ ]
                && value.${key} == gpuFrequencyCommand
              )
            )
            && check (path ++ [ key ]) value.${key}
          ) (builtins.attrNames value)
        else if builtins.isList value then
          lib.all (check path) value
        else if builtins.isString value then
          !(lib.any (part: lib.hasInfix part value) [
            "/home/"
            "/run/user/"
            "~/"
            "file://"
          ])
        else
          true;
    in
    check [ ] value;
  validWidgetStyle =
    widget:
    builtins.isString widget.type
    && lib.all (key: builtins.isInt widget.${key} || builtins.isFloat widget.${key}) [
      "cx"
      "cy"
      "box_width"
      "box_height"
      "placement_width"
      "placement_height"
    ]
    && widget.box_width > 0
    && widget.box_height > 0
    && widget.placement_width > 0
    && widget.placement_height > 0
    && lib.all (
      key:
      let
        value = widget.settings.${key};
      in
      if lib.hasSuffix "opacity" key then
        (builtins.isInt value || builtins.isFloat value) && value >= 0 && value <= 1
      else if
        lib.elem key [
          "background_radius"
          "background_padding"
        ]
      then
        builtins.isInt value && value >= 0 && value <= 32
      else if key == "color" || key == "color2" || lib.hasInfix "color" key then
        builtins.isString value
        && (
          builtins.match "#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?" value != null
          || lib.elem value [
            "surface"
            "surface_variant"
            "surface_container"
            "on_surface"
            "secondary"
            "on_secondary"
            "on_primary"
            "on_tertiary"
            "outline"
            "outline_variant"
          ]
        )
      else
        true
    ) (builtins.attrNames widget.settings);
  desktopOrder = [
    "showcase-spectrum"
    "showcase-rings"
    "showcase-clock"
    "showcase-weather"
    "showcase-network"
    "showcase-processors"
    "showcase-capacity"
  ];
  lockOrder = [
    "showcase-band-top"
    "showcase-band-bottom"
    "showcase-star-0"
    "showcase-star-1"
    "showcase-star-2"
    "showcase-inner-star-0"
    "showcase-inner-star-1"
    "showcase-inner-star-2"
    "showcase-square-left"
    "showcase-dot-upper-left"
    "showcase-dot-left"
    "showcase-square-right"
    "showcase-square-right-back"
    "showcase-small-square"
    "showcase-dot-right"
    "showcase-clock-face"
    "showcase-lock-title"
    "showcase-lock-time"
    "showcase-lock-date"
    "showcase-lock-memory"
    "showcase-lock-monitor"
    "showcase-caption"
    "showcase-lock-spectrum"
  ];
  launcherPlugins = [
    "cleboost/ssh-launcher"
    "nightwatch75/file-search"
    "3dprogramin/vscode"
    "local/sysmon-cards"
  ];
  checkHost =
    name:
    let
      host = configurations.${name};
      cfg = host.config;
      home = cfg.home-manager.users.tippy;
      umbriel = home.programs.umbriel.settings;
      noctalia = home.programs.noctalia.settings;
      previous =
        (host.extendModules {
          modules = [ { desktop.noctalia.showcase.enable = false; } ];
        }).config;
      previousHome = previous.home-manager.users.tippy;
      previousNoctalia = previousHome.programs.noctalia.settings;
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
        showcaseDefaults =
          cfg.desktop.noctalia.showcase.enable
          && host.options.desktop.noctalia.showcase.enable.default
          && cfg.desktop.noctalia.showcase.logicalWidth == 1706
          && cfg.desktop.noctalia.showcase.logicalHeight == 1066
          && host.options.desktop.noctalia.showcase.logicalWidth.default == 1706
          && host.options.desktop.noctalia.showcase.logicalHeight.default == 1066;
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
          && noctalia.lockscreen.lock_before_suspend
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
        previousSegmentedBar =
          let
            noctalia = previousNoctalia;
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
        showcaseBar =
          let
            bar = noctalia.bar.main;
          in
          bar.enabled
          && bar.position == "top"
          && bar.reserve_space
          && bar.thickness == 30
          && bar.background_opacity == 0.78
          && bar.border_width == 0
          && !bar.compositor_blur
          && !bar.shadow
          && bar.radius == 0
          && bar.concave_edge_corners
          && bar.radius_top_left == 14
          && bar.radius_top_right == 14
          && bar.radius_bottom_left == 12
          && bar.radius_bottom_right == 12
          && bar.margin_edge == 0
          && bar.margin_ends == 158
          && !bar.capsule
          && bar.capsule_group == [ ]
          &&
            bar.start == [
              "launcher"
              "screenshot"
            ]
          &&
            bar.center == [
              "temperature"
              "weather"
              "workspaces"
              "volume"
              "bluetooth"
              "network"
            ]
          &&
            bar.end == [
              "tray"
              "clock"
              "notifications"
              "session"
            ]
          && noctalia.widget.session.type == "session"
          && noctalia.widget.screenshot.type == "screenshot"
          && noctalia.widget.launcher.glyph == "rocket"
          && noctalia.widget.temperature.visualization == "none"
          && noctalia.widget.temperature.show_value
          && noctalia.widget.temperature.label_show_units
          && lib.unique (bar.start ++ bar.center ++ bar.end) == bar.start ++ bar.center ++ bar.end;
        fullVerticalArea = !noctalia.dock.enabled && umbriel.layout.gap == 0;
        noCompositorBlur =
          let
            globalWindowRule = lib.findFirst (
              rule: !(rule ? match) && (rule.blur or true) == false
            ) null umbriel.window_rule;
            noctaliaLayerRule = lib.findFirst (
              rule: (rule.match.namespace or "") == "^noctalia-.*$"
            ) null umbriel.layer_rule;
          in
          umbriel.appearance.blur.enabled == false
          && umbriel.appearance.border_width == 0
          && umbriel.appearance.outer_border_width == 0
          && !(umbriel.effects ? border)
          && umbriel.appearance.corner_radius == 12
          && umbriel.appearance.shadow.enabled
          && umbriel.appearance.shadow.softness == 18
          && globalWindowRule != null
          && noctaliaLayerRule != null
          && builtins.length umbriel.layer_rule == 1
          && noctaliaLayerRule.blur == false
          && noctaliaLayerRule.blur_popups == false
          && !(noctaliaLayerRule ? blur_ignore_alpha)
          && !(noctaliaLayerRule ? blur_optimized)
          && noctalia.shell.panel.transparency_mode == "soft"
          && !noctalia.shell.panel.borders
          && noctalia.shell.panel.border_width == 0
          && noctalia.shell.panel.shadow
          && !noctalia.notification.border
          && noctalia.notification.border_width == 0
          && !noctalia.osd.border
          && noctalia.osd.border_width == 0;
        hideUnusedWorkspaces = noctalia.widget.workspaces.hide_when_empty;
        noctaliaShellShadow =
          noctalia.shell.panel.shadow
          && noctalia.shell.shadow.alpha == 0.45
          && noctalia.shell.shadow.direction == "down";
        kittyNoBlur =
          let
            rule = lib.findFirst (rule: (rule.match.app_id or "") == "^kitty$") null umbriel.window_rule;
          in
          rule != null
          && rule.border_width == 0
          && rule.outer_border_width == 0
          && rule.border_effect == "off"
          && rule.blur == false
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
        darkShellLightApplications = noctalia.theme.mode == "light" && noctalia.theme.shell_mode == "dark";
        lockscreenBackgroundBlur =
          noctalia.shell.panel.transparency_mode == "soft"
          && noctalia.lockscreen.blur_intensity == 0.0
          && noctalia.lockscreen.tint_intensity == 0.0
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
              && login.cx == cfg.desktop.noctalia.showcase.logicalWidth / 2.0
              && login.cy > noctalia.lockscreen_widgets.widget.showcase-clock-face.cy
              && login.box_width > 0
              && login.box_height > 0
              && login.settings.layout == "regular"
              && login.settings.show_media
              && login.settings.show_media_controls
              && login.settings.show_weather
              && login.settings.show_login_button
              && !login.settings.show_password_reveal
              && !login.settings.show_session_buttons
              && login.settings.show_caps_lock
              && login.settings.show_keyboard_layout
              && login.rotation == 0
            else
              true
          );
        attachedControlCenter =
          noctalia.shell.panel.transparency_mode == "soft"
          && noctalia.shell.panel.control_center_placement == "attached"
          && noctalia.shell.panel.control_center_position == "center"
          && noctalia.shell.panel.session_placement == "floating"
          && noctalia.shell.panel.wallpaper_placement == "floating"
          && !noctalia.shell.panel.open_near_click_control_center
          && noctalia.shell.panel.open_near_click_session
          && noctalia.shell.panel.open_near_click_wallpaper
          && noctalia.control_center.sidebar == "compact"
          && noctalia.control_center.sidebar_section == "compact"
          && noctalia.control_center.show_avatar_border
          && noctalia.control_center.width == 696
          && noctalia.accessibility.ui_scale == 0.9
          &&
            map (shortcut: shortcut.type) noctalia.control_center.shortcuts == [
              "wifi"
              "bluetooth"
              "caffeine"
              "nightlight"
              "notification"
              "power_profile"
            ];
        previousRectangularLockscreen =
          name != "arx8"
          || (
            let
              widgets = previousNoctalia.lockscreen_widgets.widget;
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
            && login.settings.layout == "compact"
            && !login.settings.show_media
            && !login.settings.show_weather
            && !login.settings.show_login_button
            && !login.settings.show_password_reveal
            && !login.settings.show_session_buttons
          );
        previousDesktopCards =
          let
            noctalia = previousNoctalia;
          in
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
        previousDesktopSystemStats =
          let
            noctalia = previousNoctalia;
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
        showcaseWidgetOrder =
          noctalia.desktop_widgets.enabled
          && validOrder noctalia.desktop_widgets
          && validOrder noctalia.lockscreen_widgets
          && !(noctalia.desktop_widgets.widget ? showcase-media)
          && !(noctalia.desktop_widgets.widget ? showcase-timer)
          && noctalia.desktop_widgets.widget_order == desktopOrder
          &&
            noctalia.lockscreen_widgets.widget_order
            == lockOrder ++ lib.optional (name == "arx8") "lockscreen-login-box@eDP-1"
          &&
            map (widget: widget.type) (orderedWidgets noctalia.desktop_widgets) == [
              "audio_visualizer"
              "fancy_audio_visualizer"
              "clock"
              "weather"
              "local/sysmon-cards:card"
              "local/sysmon-cards:card"
              "local/sysmon-cards:card"
            ];
        retainedWidgetRecords =
          lib.all (
            id: noctalia.desktop_widgets.widget.${id} == previousNoctalia.desktop_widgets.widget.${id}
          ) previousNoctalia.desktop_widgets.widget_order
          &&
            lib.all
              (id: noctalia.lockscreen_widgets.widget.${id} == previousNoctalia.lockscreen_widgets.widget.${id})
              (
                lib.filter (id: id != "lockscreen-login-box@eDP-1") previousNoctalia.lockscreen_widgets.widget_order
              )
          && noctalia.desktop_widgets.widget.monitor-gpu.settings.gpu_frequency_command != [ ];
        onlyHostLoginIsExplicit =
          let
            widgets = noctalia.lockscreen_widgets.widget;
            logins = lib.filter (id: widgets.${id}.type == "login_box") (builtins.attrNames widgets);
          in
          logins == lib.optional (name == "arx8") "lockscreen-login-box@eDP-1"
          && lib.all (widget: widget.type != "login_box") (orderedWidgets noctalia.desktop_widgets);
        showcaseWidgetStyles = lib.all validWidgetStyle (
          orderedWidgets noctalia.desktop_widgets ++ orderedWidgets noctalia.lockscreen_widgets
        );
        noImportedPathsOrCommands =
          let
            gpuFrequencyCommand =
              previousNoctalia.desktop_widgets.widget.monitor-gpu.settings.gpu_frequency_command;
          in
          builtins.isList gpuFrequencyCommand
          && builtins.length gpuFrequencyCommand == 1
          && builtins.isString (builtins.head gpuFrequencyCommand)
          &&
            builtins.match "/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-noctalia-gpu-clock" (
              builtins.head gpuFrequencyCommand
            ) != null
          &&
            noctalia.desktop_widgets.widget.showcase-processors.settings.gpu_frequency_command
            == gpuFrequencyCommand
          && safeShowcaseValue gpuFrequencyCommand (
            lib.genAttrs noctalia.desktop_widgets.widget_order (id: noctalia.desktop_widgets.widget.${id})
          )
          && safeShowcaseValue [ ] (orderedWidgets noctalia.lockscreen_widgets)
          && safeShowcaseValue [ ] noctalia.control_center
          && lib.all (path: lib.hasPrefix "/nix/store/" path) [
            noctalia.wallpaper.default.path
            noctalia.lockscreen.wallpaper
          ];
        showcaseNativeWidgets =
          let
            desktop = noctalia.desktop_widgets.widget;
            lock = noctalia.lockscreen_widgets.widget;
            spectra = [
              desktop.showcase-spectrum
              lock.showcase-lock-spectrum
            ];
          in
          lib.all (
            widget:
            widget.type == "audio_visualizer"
            && widget.flip_y
            && !widget.settings.centered
            && !widget.settings.background
            && widget.settings.bands >= 4
            && widget.settings.bands <= 128
          ) spectra
          && desktop.showcase-rings.box_width == desktop.showcase-rings.box_height
          && desktop.showcase-rings.settings.visualization_mode == "wave_rings"
          && desktop.showcase-rings.settings.inner_diameter == 0.7
          && desktop.showcase-rings.settings.ring_opacity == 0.9
          && desktop.showcase-rings.settings.bloom_intensity == 0.6
          && desktop.showcase-clock.settings.format == "{:%H:%M:%S}"
          && !(desktop ? showcase-monitor)
          &&
            lib.all (widget: widget.type == "local/sysmon-cards:card" && widget.settings.layout == "overview")
              [
                desktop.showcase-processors
                desktop.showcase-capacity
                desktop.showcase-network
              ]
          && desktop.showcase-processors.settings.group == "processors"
          && desktop.showcase-capacity.settings.group == "capacity"
          && desktop.showcase-network.settings.group == "network"
          && lock.showcase-lock-time.settings.format == "{:%H:%M}"
          && lock.showcase-lock-date.settings.format == "{:%a,  %b  %d}"
          && !(lock ? showcase-volume)
          && lock.showcase-lock-memory.type == "sysmon"
          && lock.showcase-lock-memory.settings.display == "graph"
          && lock.showcase-lock-memory.settings.stat == "ram_pct"
          && lock.showcase-lock-memory.settings.stat2 == "swap_pct"
          && lock.showcase-lock-monitor.type == "sysmon"
          && lock.showcase-lock-monitor.settings.display == "graph"
          && lock.showcase-lock-monitor.settings.stat == "cpu_usage"
          && lock.showcase-lock-monitor.settings.stat2 == "cpu_temp"
          && noctalia.location.auto_locate
          && noctalia.weather.enabled
          && noctalia.weather.unit == "metric"
          && near lock.showcase-band-top.rotation (-0.27045175433158875)
          && near lock.showcase-band-bottom.rotation (-0.27045175433158875)
          && !(lock ? showcase-clock-back)
          && !(lock ? showcase-login-back)
          && !(lock ? showcase-login-edge)
          && lock.showcase-clock-face.settings.background_opacity == 0.87;
        showcaseWallpaper =
          noctalia.wallpaper.default.path == "${host.pkgs.wallpaper.showcase}/wallpaper.png"
          && noctalia.lockscreen.wallpaper == "${host.pkgs.wallpaper.showcaseLockscreen}/lockscreen.png"
          && noctalia.wallpaper.fill_mode == "crop"
          &&
            cfg.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path
            == "${host.pkgs.wallpaper.showcase}/wallpaper.png"
          && cfg.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.blur == 0.0
          && cfg.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.tint == 0.0;
        hdrWallpaper =
          if name == "arx8" then
            noctalia.wallpaper.enabled
            &&
              home.systemd.user.services.hdr-wallpaper.Service.ExecStart == [
                "${host.pkgs.hdr-wallpaper}/bin/hdr-wallpaper eDP-1 ${host.pkgs.wallpaper.showcaseHdr}/wallpaper-hdr.png"
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
        hdrOnlyImageChanged =
          if name == "arx8" then
            let
              current = home.systemd.user.services.hdr-wallpaper;
              old = previousHome.systemd.user.services.hdr-wallpaper;
            in
            builtins.removeAttrs current [ "Service" ] == builtins.removeAttrs old [ "Service" ]
            &&
              builtins.removeAttrs current.Service [ "ExecStart" ]
              == builtins.removeAttrs old.Service [ "ExecStart" ]
          else
            !(previousHome.systemd.user.services ? hdr-wallpaper);
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
          && noctalia.theme.shell_mode == "dark"
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
          && umbriel.keybinds.Mod.action == "spawn ${lib.getExe home.programs.vicinae.package} toggle"
          && !umbriel.keybinds.Mod.repeat
          && !(umbriel.keybinds ? "Alt+Tab")
          && !(umbriel.keybinds ? "Mod+Ctrl+Left")
          &&
            umbriel.keybinds."Mod+L".action
            == "spawn ${lib.getExe home.programs.noctalia.package} msg session lock"
          && !umbriel.keybinds."Mod+L".repeat
          && umbriel.keybinds."Mod+Right" == "window-focus-right"
          && umbriel.keybinds."Mod+H" == "window-focus-left"
          && umbriel.keybinds."Mod+Comma" == "window-consume-left"
          && umbriel.keybinds."Mod+Period" == "window-consume-right"
          && umbriel.keybinds."Mod+Space" == "scratchpad-toggle"
          && umbriel.keybinds."Mod+Escape" == "session-quit"
          && umbriel.keybinds."Mod+O".action == "overview-toggle";
        launcherSearch =
          let
            desktopLocalSource = lib.findFirst (
              source: source.name == "desktop-local"
            ) null noctalia.plugins.source;
            previousDesktopLocalSource = lib.findFirst (
              source: source.name == "desktop-local"
            ) null previousNoctalia.plugins.source;
          in
          noctalia.plugins.enabled == launcherPlugins
          && !(noctalia.plugin_settings ? "noctalia/timer")
          && noctalia.plugins.auto_update == "none"
          && lib.any (source: source.kind == "path" && source.enabled) noctalia.plugins.source
          && desktopLocalSource != null
          && desktopLocalSource.kind == "path"
          && desktopLocalSource.enabled
          && lib.hasPrefix "/nix/store/" desktopLocalSource.location
          && desktopLocalSource == previousDesktopLocalSource
          && lib.all (
            source: source.name != "noctalia/timer" && !lib.hasSuffix "/timer" source.location
          ) noctalia.plugins.source
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
            && umbriel.output."eDP-1".workspaces == "dynamic"
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
      vicinae =
        let
          launcher = home.programs.vicinae;
          launcherService = home.systemd.user.services.vicinae;
          disabledHome =
            (host.extendModules {
              modules = [ { desktop.noctalia.enable = lib.mkForce false; } ];
            }).config.home-manager.users.tippy;
        in
        assertChecks "${name}/vicinae" {
          officialPackage =
            launcher.enable
            && launcher.package.outPath == host.pkgs.vicinae.outPath
            && lib.elem "vicinae" homePackages;
          nativeLifecycle =
            launcher.systemd.enable
            && launcher.systemd.autoStart
            && launcher.systemd.target == "umbriel-session.target"
            && launcherService.Unit.After == [ "umbriel-session.target" ]
            && launcherService.Unit.PartOf == [ "umbriel-session.target" ]
            && launcherService.Install.WantedBy == [ "umbriel-session.target" ]
            && launcherService.Service.ExecStart == [ "${lib.getExe launcher.package} server" ]
            && !(lib.any (command: lib.hasInfix "vicinae" command) umbriel.general.autostart)
            && !(lib.any (path: lib.hasInfix "vicinae" path) (builtins.attrNames autostartFiles));
          writableUserSettings =
            launcher.mutableSettings
            && home.xdg.configFile."vicinae/home-manager.json".enable
            && !(home.xdg.configFile ? "vicinae/settings.json")
            && lib.any (value: lib.hasInfix "VICINAE_OVERRIDES=" value) launcherService.Service.Environment;
          onboardingDefaultsToComplete =
            lib.hasInfix "home.activation.vicinaeOnboarding" (
              builtins.readFile ../home-manager/modules/desktop/vicinae.nix
            )
            && lib.hasInfix ''{"version":1,"completedAt":""}'' (
              builtins.readFile ../home-manager/modules/desktop/vicinae.nix
            )
            && lib.hasInfix ''if [ ! -e "$state_file" ]'' (
              builtins.readFile ../home-manager/modules/desktop/vicinae.nix
            )
            && lib.elem ".local/state/vicinae" (directories home.home.global-persistence.directories);
          translucentWithoutBlur =
            launcher.settings.theme.light.name == "sandstone-light"
            && launcher.settings.theme.dark.name == "sandstone-dark"
            && launcher.themes.sandstone-dark.meta.inherits == "vicinae-dark"
            && launcher.themes.sandstone-light.meta.inherits == "vicinae-light"
            && home.xdg.dataFile."vicinae/themes/sandstone-dark.toml".enable
            && home.xdg.dataFile."vicinae/themes/sandstone-light.toml".enable
            && launcher.settings.launcher_window.opacity == 0.88
            && launcher.settings.launcher_window.material == "none"
            && launcher.settings.launcher_window.rounding == 12
            && launcher.settings.launcher_window.client_side_decorations.border_width == 0
            && launcher.settings.launcher_window.client_side_decorations.shadow_size == 18;
          nvidiaRenderer =
            !(lib.elem "nvidia" cfg.services.xserver.videoDrivers)
            || lib.elem "QSG_RHI_BACKEND=vulkan" launcherService.Service.Environment;
          keyboardAndRocket =
            umbriel.keybinds.Mod.action == "spawn ${lib.getExe launcher.package} toggle"
            && !umbriel.keybinds.Mod.repeat
            && noctalia.widget.launcher.type == "launcher"
            && noctalia.widget.launcher.glyph == "rocket"
            && noctalia.widget.launcher.actions.left == "exec vicinae toggle";
          cheatsheetOnDemand =
            umbriel.general.show_cheatsheet == false
            && cfg.programs.nvf.settings.vim.binds.cheatsheet.enable == false
            && umbriel.keybinds."Mod+Shift+Slash".action == "cheatsheet-toggle"
            && !umbriel.keybinds."Mod+Shift+Slash".repeat
            &&
              lib.elem
                {
                  directory = ".local/state/vicinae";
                  mode = "0700";
                }
                (
                  map (
                    entry:
                    if builtins.isAttrs entry then
                      entry
                    else
                      {
                        directory = entry;
                        mode = null;
                      }
                  ) home.home.global-persistence.directories
                );
          lockAndOverviewRetained =
            umbriel.keybinds."Mod+L".action
            == "spawn ${lib.getExe home.programs.noctalia.package} msg session lock"
            && !umbriel.keybinds."Mod+L".repeat
            && umbriel.keybinds."Mod+O".action == "overview-toggle"
            && !noctalia.shell.umbriel_overview_type_to_launch_enabled
            && home.programs.noctalia.enable
            && noctalia.lockscreen.enabled
            && cfg.programs.noctalia.systemd.enable;
          independentOfShowcase =
            previousHome.programs.vicinae.enable
            && previousHome.systemd.user.services.vicinae == launcherService
            && !previousNoctalia.shell.umbriel_overview_type_to_launch_enabled;
          disabledWithNoctalia =
            !disabledHome.programs.vicinae.enable
            && !(disabledHome.systemd.user.services ? vicinae)
            && !(disabledHome.xdg.configFile ? "vicinae/home-manager.json");
        };
      showcaseDisabled = assertChecks "${name}/showcase-disabled" {
        sameSessionAndServices =
          !previous.desktop.noctalia.showcase.enable
          && previous.desktop.noctalia.enable
          && previous.desktop.defaultSession == cfg.desktop.defaultSession
          && previous.systemd.user.services.noctalia.serviceConfig == service.serviceConfig
          && previous.systemd.user.services.noctalia.after == service.after
          && previous.systemd.user.services.noctalia.before == service.before
          && previous.systemd.user.services.noctalia.partOf == service.partOf
          && previous.systemd.user.services.noctalia.wantedBy == service.wantedBy
          &&
            lib.recursiveUpdate previous.services.displayManager.noctalia-greeter.settings {
              appearance.wallpaper.path =
                cfg.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path;
            } == cfg.services.displayManager.noctalia-greeter.settings
          &&
            builtins.attrNames previousHome.systemd.user.services
            == builtins.attrNames home.systemd.user.services;
        originalThemeAndPopups =
          previousNoctalia.theme.mode == "light"
          && previousNoctalia.theme.shell_mode == "light"
          && previousNoctalia.shell.panel.control_center_placement == "floating"
          && previousNoctalia.shell.panel.open_near_click_control_center
          && previousNoctalia.control_center.sidebar == "full"
          && previousNoctalia.control_center.width == 700;
        originalLockOrder =
          previousNoctalia.lockscreen_widgets.widget_order == [
            "lock-cpu"
            "lock-network"
            "lock-ram"
            "lock-clock"
            "lock-calendar"
          ]
          ++ lib.optional (name == "arx8") "lockscreen-login-box@eDP-1"
          && validOrder previousNoctalia.lockscreen_widgets
          && validOrder previousNoctalia.desktop_widgets;
        originalPlugins =
          previousNoctalia.plugins.enabled == launcherPlugins
          && previousNoctalia.plugins.auto_update == "none"
          && lib.all (widget: widget.type != "noctalia/timer:desktop") (
            builtins.attrValues previousNoctalia.desktop_widgets.widget
          )
          && lib.all (id: !lib.hasPrefix "showcase-" id) (
            builtins.attrNames previousNoctalia.desktop_widgets.widget
            ++ builtins.attrNames previousNoctalia.lockscreen_widgets.widget
          )
          && lib.any (
            source: source.name == "desktop-local" && source.kind == "path" && source.enabled
          ) previousNoctalia.plugins.source;
        originalResources =
          previousNoctalia.wallpaper.default.path == "${host.pkgs.wallpaper}/wallpaper.jpg"
          && previousNoctalia.lockscreen.wallpaper == ""
          &&
            previous.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path
            == previousNoctalia.wallpaper.default.path
          && (
            name != "arx8"
            ||
              previousHome.systemd.user.services.hdr-wallpaper.Service.ExecStart == [
                "${host.pkgs.hdr-wallpaper}/bin/hdr-wallpaper eDP-1 ${host.pkgs.wallpaper.hdr}/wallpaper-hdr.png"
              ]
          );
      };
      # Static contracts: each case regenerates boxes for its logical canvas.
      # Physical sizes exercise mixed scales, without output discovery or docking.
      showcaseGeometry =
        lib.mapAttrs
          (
            label: output:
            let
              width = output.width * 1.0;
              height = output.height * 1.0;
              variant =
                (host.extendModules {
                  modules = [
                    {
                      desktop.noctalia.showcase = {
                        logicalWidth = output.width;
                        logicalHeight = output.height;
                      };
                    }
                  ];
                }).config;
              settings = variant.home-manager.users.tippy.programs.noctalia.settings;
              desktop = settings.desktop_widgets;
              lock = settings.lockscreen_widgets;
              desktopScale = lib.min (width / 1920.0) (height / 1079.0);
              lockScale = lib.min (width / 1920.0) (height / 1080.0);
              lockDy = (height - 1080.0 * lockScale) / 2.0;
              column = map (id: desktop.widget.${id}) [
                "showcase-clock"
                "showcase-weather"
                "showcase-network"
                "showcase-processors"
                "showcase-capacity"
              ];
              active = orderedWidgets desktop ++ orderedWidgets lock;
              ordinaryLock = lib.filter (widget: widget.type != "label") (orderedWidgets lock);
              actualWidth = builtins.floor (output.physicalWidth / output.scale) * 1.0;
              actualHeight = builtins.floor (output.physicalHeight / output.scale) * 1.0;
              mapped = map (remap actualWidth actualHeight) (orderedWidgets desktop ++ ordinaryLock);
              login = lock.widget."lockscreen-login-box@eDP-1";
              renderedMetric = value: builtins.floor (value * settings.accessibility.ui_scale + 0.5);
              metricClose = actual: expected: actual - expected > -1.0 && actual - expected < 1.0;
            in
            assertChecks "${name}/showcase-geometry/${label}" {
              sameLogicalPlacement =
                lib.all (widget: widget.placement_width == width && widget.placement_height == height) active
                && lib.all (widget: !(widget ? anchor_top_right)) active
                && lib.all (widget: !(widget ? anchor_below_bar)) active
                && lib.all validWidgetStyle active;
              spectrumTouchesBar =
                near desktop.widget.showcase-spectrum.cx (width / 2.0)
                && near (
                  desktop.widget.showcase-spectrum.cy - desktop.widget.showcase-spectrum.box_height / 2.0
                ) settings.bar.main.thickness
                && desktop.widget.showcase-spectrum.flip_y
                && !desktop.widget.showcase-spectrum.settings.show_when_idle
                && !desktop.widget.showcase-spectrum.settings.show_wave
                && desktop.widget.showcase-rings.settings.fade_when_idle;
              activeCardBounds =
                lib.all (inside width height) (orderedWidgets desktop ++ ordinaryLock)
                && lib.all (widget: widget.cy - widget.box_height / 2 >= settings.bar.main.thickness) column;
              anchoredColumn =
                lib.all (widget: near (width - widget.cx - widget.box_width / 2) (48.0 * desktopScale)) column
                && lib.all (widget: near widget.box_width (256.0 * desktopScale)) column
                && lib.all (value: value) (
                  lib.zipListsWith (widget: cy: near widget.cy (cy * desktopScale)) column [
                    112.0
                    212.0
                    346.0
                    502.0
                    658.0
                  ]
                )
                && lib.all (value: value) (
                  lib.zipListsWith (widget: height: near widget.box_height (height * desktopScale)) column [
                    80.0
                    104.0
                    148.0
                    148.0
                    148.0
                  ]
                )
                && lib.all (gap: gap >= 8.0 * desktopScale - 0.001) (
                  lib.zipListsWith (a: b: b.cy - b.box_height / 2 - a.cy - a.box_height / 2) (lib.take (
                    builtins.length column - 1
                  ) column) (lib.drop 1 column)
                );
              centredLockSubject =
                near lock.widget.showcase-clock-face.cx (width / 2 + (952.0 - 960.0) * lockScale)
                && near lock.widget.showcase-clock-face.cy (lockDy + 468.0 * lockScale)
                && near lock.widget.showcase-clock-face.box_width (464.0 * lockScale)
                && near lock.widget.showcase-clock-face.box_height (368.0 * lockScale)
                && near lock.widget.showcase-lock-memory.box_width (208.0 * lockScale)
                && (
                  name != "arx8"
                  || (
                    near login.cx (width / 2)
                    && near login.cy (lockDy + 933.0 * lockScale)
                    && near login.box_width (810.0 * lockScale)
                    # Native regular login height is normalized separately from placement.
                    && login.box_height == 150.0
                    && login.rotation == 0
                    && inside width height login
                  )
                );
              scaledBackgroundMetrics =
                metricClose (renderedMetric desktop.widget.showcase-clock.settings.background_radius) (
                  16.0 * desktopScale
                )
                && metricClose (renderedMetric desktop.widget.showcase-clock.settings.background_padding) (
                  12.0 * desktopScale
                )
                && metricClose (renderedMetric lock.widget.showcase-lock-memory.settings.background_radius) (
                  12.0 * lockScale
                )
                && metricClose (renderedMetric lock.widget.showcase-lock-memory.settings.background_padding) (
                  8.0 * lockScale
                );
              decorationsMayBleed =
                !inside width height lock.widget.showcase-band-top
                && !inside width height lock.widget.showcase-band-bottom
                && lock.widget.showcase-band-top.type == "label"
                && lock.widget.showcase-band-bottom.type == "label";
              mixedScaleLogicalBounds =
                lib.all (inside actualWidth actualHeight) mapped
                && lib.all (
                  widget: near widget.placement_width actualWidth && near widget.placement_height actualHeight
                ) mapped
                &&
                  near (remap actualWidth actualHeight desktop.widget.showcase-clock).box_width
                    desktop.widget.showcase-clock.box_width;
              outputConfigurationUnchanged =
                (variant.home-manager.users.tippy.programs.umbriel.settings.output or { })
                == (umbriel.output or { })
                &&
                  (variant.services.displayManager.noctalia-greeter.settings.output or { })
                  == (cfg.services.displayManager.noctalia-greeter.settings.output or { });
            }
          )
          {
            fhd = {
              width = 1920;
              height = 1080;
              physicalWidth = 1920.0;
              physicalHeight = 1080.0;
              scale = 1.0;
            };
            arx8Fractional = {
              width = 1706;
              height = 1066;
              physicalWidth = 2560.0;
              physicalHeight = 1600.0;
              scale = 1.5;
            };
            hdDouble = {
              width = 1280;
              height = 720;
              physicalWidth = 2560.0;
              physicalHeight = 1440.0;
              scale = 2.0;
            };
            sixteenTen = {
              width = 1920;
              height = 1200;
              physicalWidth = 2880.0;
              physicalHeight = 1800.0;
              scale = 1.5;
            };
          };
      # A smaller output cannot inherit the same bounds guarantee merely by
      # remapping the default canvas: the native mapper never shrinks its boxes.
      centreOnlyRemap = assertChecks "${name}/centre-only-remap" (
        let
          clock = noctalia.desktop_widgets.widget.showcase-clock;
          smaller = remap 1280.0 720.0 clock;
          narrower = remap 1024.0 576.0 clock;
        in
        {
          boxIsUnchanged = smaller.box_width == clock.box_width && smaller.box_height == clock.box_height;
          centreMoves =
            near smaller.cx (clock.cx * 1280.0 / clock.placement_width)
            && near smaller.cy (clock.cy * 720.0 / clock.placement_height);
          smallerOutputIsNotResizedPreset =
            inside 1280.0 720.0 smaller && !near smaller.box_width (256.0 * 1280.0 / 1920.0);
          narrowerOutputCanOverflow = !inside 1024.0 576.0 narrower;
        }
      );
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
            variant.desktop.voiceInput.enable
            && variant.desktop.voiceInput.streaming
            && variantHome.xdg.configFile ? "vocotype/config.json"
            && (
              if framework == "ibus" then
                !variant.i18n.inputMethod.ibus.waylandFrontend
                && variantHome.home.sessionVariables.GTK_IM_MODULE == "ibus"
                && variantHome.home.sessionVariables.QT_IM_MODULE == "ibus"
                && variantHome.xdg.configFile."ibus/rime".recursive
                && lib.any (
                  package: lib.hasInfix "vocotype" (lib.getName package)
                ) variant.i18n.inputMethod.ibus.engines
                && toString variantHome.dconf.settings."desktop/ibus/general".preload-engines == "@as ['rime']"
                && !(variantHome.xdg.configFile ? "fcitx5/config")
                && !(variantHome.xdg.dataFile ? "fcitx5/rime")
                && !(variantHome.xdg.configFile ? "autostart/org.fcitx.Fcitx5.desktop")
                && !(variantHome.systemd.user.services ? "org.freedesktop.IBus.session.GNOME")
              else
                variant.i18n.inputMethod.fcitx5.waylandFrontend
                && variantHome.home.sessionVariables.QT_IM_MODULE == "fcitx"
                && variantHome.xdg.dataFile."fcitx5/rime".recursive
                && variantHome.systemd.user.services ? "vocotype-fcitx5-backend"
                && lib.any (
                  package: lib.hasInfix "vocotype" (lib.getName package)
                ) variant.i18n.inputMethod.fcitx5.addons
                && !(variantHome.xdg.configFile ? "ibus/rime")
            );
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
