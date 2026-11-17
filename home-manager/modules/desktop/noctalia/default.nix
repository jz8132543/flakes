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
  baseline = builtins.fromJSON (builtins.readFile ./noctalia-base-settings.json);
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
  settings = lib.recursiveUpdate baseline {
    shell.screenshot.directory = "${pictures}/Screenshots";
    wallpaper = {
      default.path = "${pkgs.wallpaper}/wallpaper.jpg";
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
      settings = lib.mapAttrsRecursive (_: value: lib.mkDefault value) settings;
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
