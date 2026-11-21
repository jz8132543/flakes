{
  config,
  inputs,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  enabled = lib.attrByPath [ "desktop" "noctalia" "enable" ] false osConfig;
  showcase = lib.attrByPath [ "desktop" "noctalia" "showcase" ] {
    enable = false;
    logicalWidth = 1706;
    logicalHeight = 1066;
  } osConfig;
  baseline = builtins.fromJSON (builtins.readFile ./noctalia-base-settings.json);
  showcaseReference = builtins.fromJSON (builtins.readFile ./noctalia-showcase-settings.json);
  # PlacementMapper remaps centres only. Size the boxes once in logical pixels;
  # the lockscreen uses a centred safe area, while the desktop column hugs the edge.
  placeWidgets =
    referenceHeight: widgets:
    let
      width = showcase.logicalWidth * 1.0;
      height = showcase.logicalHeight * 1.0;
      scale = lib.min (width / 1920.0) (height / referenceHeight);
      dx = (width - scale * 1920.0) / 2.0;
      dy = (height - scale * referenceHeight) / 2.0;
    in
    lib.mapAttrs (
      _: widget:
      let
        anchored = widget.anchor_top_right or false;
      in
      (builtins.removeAttrs widget [
        "anchor_top_right"
        "anchor_below_bar"
      ])
      // {
        cx = if anchored then width - scale * (1920.0 - widget.cx) else dx + scale * widget.cx;
        cy =
          if widget.anchor_below_bar or false then
            showcaseReference.bar.main.thickness + scale * widget.box_height / 2.0
          else
            (if anchored then 0.0 else dy) + scale * widget.cy;
        box_width = scale * widget.box_width;
        box_height = scale * widget.box_height;
        placement_width = width;
        placement_height = height;
        settings = lib.mapAttrs (
          key: value:
          if
            lib.elem key [
              "background_radius"
              "background_padding"
            ]
          then
            # Native backgrounds apply ui_scale separately from the box size.
            lib.min 32 (builtins.floor (scale * value / showcaseReference.accessibility.ui_scale + 0.5))
          else
            value
        ) widget.settings;
      }
    ) widgets;
  showcaseSettings =
    lib.recursiveUpdate
      (builtins.removeAttrs showcaseReference [
        "desktop_widgets"
        "lockscreen_widgets"
      ])
      {
        bar.main.margin_ends = builtins.floor (showcase.logicalWidth * 0.093);
        desktop_widgets = {
          inherit (showcaseReference.desktop_widgets) widget_order;
          widget = lib.recursiveUpdate (placeWidgets 1079.0 showcaseReference.desktop_widgets.widget) {
            showcase-processors.settings.gpu_frequency_command = [ "${gpuClock}" ];
          };
        };
        lockscreen_widgets = {
          inherit (showcaseReference.lockscreen_widgets) widget_order;
          widget = placeWidgets 1080.0 showcaseReference.lockscreen_widgets.widget;
        };
        wallpaper.default.path = "${pkgs.wallpaper.showcase}/wallpaper.png";
        lockscreen.wallpaper = "${pkgs.wallpaper.showcaseLockscreen}/lockscreen.png";
      };
  # The host's previous authentication card has ordinary priority. Override only
  # its owned leaves and order, leaving the legacy widgets available when disabled.
  lockScale = lib.min (showcase.logicalWidth / 1920.0) (showcase.logicalHeight / 1080.0);
  showcaseLogin = {
    type = "login_box";
    output = "eDP-1";
    cx = showcase.logicalWidth / 2.0;
    cy = (showcase.logicalHeight - lockScale * 1080.0) / 2.0 + lockScale * 933.0;
    box_width = lockScale * 810.0;
    # Native regular login height is recomputed from the controls, not scaled.
    box_height = 150.0;
    placement_width = showcase.logicalWidth * 1.0;
    placement_height = showcase.logicalHeight * 1.0;
    rotation = 0.0;
    settings = {
      layout = "regular";
      show_media = true;
      show_media_controls = true;
      show_weather = true;
      show_login_button = true;
      show_password_reveal = false;
      show_session_buttons = false;
      show_unlock_hint = true;
      show_caps_lock = true;
      show_keyboard_layout = true;
      center_password_text = true;
      background_color = "surface_container";
      background_opacity = 0.88;
      background_radius = 18;
      input_opacity = 1.0;
      input_radius = 9;
    };
  };
  # Match tmux's Dracula background while keeping theme-generated dark ANSI colours.
  kittyTemplate = pkgs.writeText "noctalia-kitty-dark.conf" (
    lib.replaceStrings
      [
        "{{colors.terminal_background.default.hex}}"
        "{{colors.terminal_foreground.default.hex}}"
        "{{colors.terminal_cursor_text.default.hex}}"
        ".default."
      ]
      [ "#282a36" "#f8f8f2" "#282a36" ".dark." ]
      (builtins.readFile "${inputs.noctalia}/assets/templates/kitty/kitty.conf")
  );
  launcherPluginSource = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "community-plugins";
    rev = "3f6037a1ee9ce3a1028f66a94bf469d13276b7ec";
    hash = "sha256-UXxQUp02YFqayCcYz8pr5OWPVuicDgGAGCxAasuz56g=";
  };
  launcherPlugins = pkgs.linkFarm "noctalia-launcher-plugins" (
    map
      (name: {
        inherit name;
        path = "${launcherPluginSource}/${name}";
      })
      [
        "ssh-launcher"
        "file-search"
        "vscode"
      ]
  );
  desktopPlugins = pkgs.linkFarm "noctalia-desktop-plugins" [
    {
      name = "sysmon-cards";
      path = ./sysmon-cards;
    }
  ];
  gpuClock = pkgs.writeShellScript "noctalia-gpu-clock" ''
    # Only query an unambiguous, already-active NVIDIA GPU, matching the native sampler.
    cards=(/sys/class/drm/card[0-9]*)
    devices=()
    for card in "''${cards[@]}"; do
      [[ "''${card##*/}" =~ ^card[0-9]+$ ]] && devices+=("$card/device")
    done
    [[ ''${#devices[@]} == 1 ]] || exit 1
    device="''${devices[0]}"
    [[ $(< "$device/vendor") == 0x10de ]] || exit 1
    [[ $(< "$device/power/runtime_status") == active ]] || exit 1
    while IFS='=' read -r key value; do
      [[ "$key" == PCI_SLOT_NAME ]] && slot="$value"
    done < "$device/uevent"
    [[ -n "''${slot:-}" ]] || exit 1
    exec ${pkgs.coreutils}/bin/timeout --kill-after=1s 3s \
      /run/current-system/sw/bin/nvidia-smi --id="$slot" \
      --query-gpu=clocks.current.graphics --format=csv,noheader,nounits
  '';
  pictures =
    lib.replaceStrings
      [ "$HOME" "\${HOME}" ]
      [
        config.home.homeDirectory
        config.home.homeDirectory
      ]
      config.xdg.userDirs.pictures;
  settings =
    lib.recursiveUpdate
      (lib.recursiveUpdate baseline (lib.optionalAttrs showcase.enable showcaseSettings))
      {
        shell.screenshot.directory = "${pictures}/Screenshots";
        wallpaper = {
          default.path =
            if showcase.enable then
              "${pkgs.wallpaper.showcase}/wallpaper.png"
            else
              "${pkgs.wallpaper}/wallpaper.jpg";
          directory = "${pictures}/Wallpapers";
        };
        theme.templates.user.kitty = {
          input_path = "${kittyTemplate}";
          output_path = "$XDG_STATE_HOME/noctalia/kitty-theme.conf";
          post_hook = "${pkgs.procps}/bin/pkill -USR1 -u ${lib.escapeShellArg config.home.username} -x '(kitty|[.]kitty-wrapped_*)' || true";
        };
        plugins = {
          enabled = [
            "cleboost/ssh-launcher"
            "nightwatch75/file-search"
            "3dprogramin/vscode"
            "local/sysmon-cards"
          ];
          source = baseline.plugins.source ++ [
            {
              name = "launcher-pinned";
              kind = "path";
              location = "${launcherPlugins}";
              enabled = true;
            }
            {
              name = "desktop-local";
              kind = "path";
              location = "${desktopPlugins}";
              enabled = true;
            }
          ];
        };
        desktop_widgets.widget.monitor-gpu.settings.gpu_frequency_command = [ "${gpuClock}" ];
        plugin_settings = {
          "nightwatch75/file-search" = {
            search_folder = "~";
            show_hidden = false;
            space_enabled = false;
          };
          "3dprogramin/vscode" = {
            editor = "code";
            show_git = false;
          };
        };
      };
in
{
  imports = [ inputs.noctalia.homeModules.default ];

  config = lib.mkIf enabled {
    window-manager.polkit.enable = lib.mkDefault false;
    xdg.dataFile."dbus-1/services/org.freedesktop.secrets.service".source =
      "${pkgs.gnome-keyring}/share/dbus-1/services/org.freedesktop.secrets.service";
    home.packages = with pkgs; [
      findutils
      fzf
      openssh
      sqlite
      xdg-utils
    ];
    programs.kitty.extraConfig = lib.mkAfter ''
      # The shell writes only this palette, never Home Manager's kitty.conf.
      include ${config.xdg.stateHome}/noctalia/kitty-theme.conf
    '';
    programs.kitty.settings = lib.mapAttrs (_: value: lib.mkDefault value) {
      background_opacity = 0.80;
      dynamic_background_opacity = true;
      transparent_background_colors = "#282a36";
      window_border_width = 0;
      window_margin_width = 0;
      window_padding_width = 0;
      draw_minimal_borders = true;
    };
    programs.noctalia = {
      enable = true;
      package = osConfig.programs.noctalia.package;
      systemd.enable = false;
      checkConfig = true;
      # Per-key defaults remain overridable by other HM modules. Noctalia's GUI
      # independently writes settings.toml in stateHome, which wins at runtime.
      settings = lib.mkMerge [
        (lib.mapAttrsRecursive (_: value: lib.mkDefault value) settings)
        { shell.umbriel_overview_type_to_launch_enabled = false; }
        (lib.mkIf showcase.enable {
          lockscreen_widgets = {
            widget_order = lib.mkForce (
              showcaseReference.lockscreen_widgets.widget_order
              ++ lib.optional (osConfig.networking.hostName == "arx8") "lockscreen-login-box@eDP-1"
            );
            widget = lib.optionalAttrs (osConfig.networking.hostName == "arx8") {
              "lockscreen-login-box@eDP-1" = lib.mapAttrsRecursive (_: value: lib.mkForce value) showcaseLogin;
            };
          };
        })
      ];
    };

    # GUI overrides and encrypted clipboard history belong to the writable state.
    home.global-persistence.directories = lib.mkIf config.home.global-persistence.enabled (
      map
        (base: {
          directory = lib.removePrefix "${config.home.homeDirectory}/" "${base}/noctalia";
          mode = "0700";
        })
        [
          config.xdg.configHome
          config.xdg.stateHome
          config.xdg.dataHome
        ]
    );
  };
}
