{
  pkgs,
  lib,
  config,
  osConfig ? { },
  ...
}:
let
  # ▼▼▼ 在这里调整输入法的字体大小 ▼▼▼
  kimpanelFontSize = "26pt";
  # ▲▲▲ 在这里调整输入法的字体大小 ▲▲▲

  imFramework = lib.attrByPath [ "desktop" "inputMethod" "framework" ] "ibus" osConfig;
  gsconnectDomains = lib.attrByPath [ "desktop" "kdeconnect" "customDomains" ] [ ] osConfig;
  extensionPkgs = with pkgs.gnomeExtensions; [
    appindicator
    dash-to-dock
    clipboard-history
    upower-battery
    alphabetical-app-grid
    system-monitor-next
    gsconnect
    # caffeine
    # allow-locked-remote-desktop
    user-themes
    blur-my-shell
    # fcitx5
    (kimpanel.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        sed -i -e '/isLookupTableVertical() {/,/}/c\    isLookupTableVertical() { return false; }' $out/share/gnome-shell/extensions/kimpanel@kde.org/extension.js
        echo ".kimpanel-box, .kimpanel-candidate-item, .kimpanel-preedit-text, .kimpanel-candidate-text { font-family: 'LXGW WenKai GB', 'LXGW WenKai', sans-serif !important; font-size: ${kimpanelFontSize} !important; }" >> $out/share/gnome-shell/extensions/kimpanel@kde.org/stylesheet.css
      '';
    }))
  ];

  inherit (lib.hm.gvariant)
    mkArray
    mkTuple
    mkString
    mkUint32
    type
    ;
  # Toggle the GNOME/Mutter display power state via DBus.
  # writeShellApplication ensures busctl and awk are always in PATH
  # without relying on the ambient system PATH.
  toggleScreen = pkgs.writeShellApplication {
    name = "gnome-toggle-screen";
    runtimeInputs = [
      pkgs.systemd # busctl
      pkgs.gawk
    ];
    text = ''
      STATE=$(busctl --user get-property \
        org.gnome.Mutter.DisplayConfig \
        /org/gnome/Mutter/DisplayConfig \
        org.gnome.Mutter.DisplayConfig PowerSaveMode \
        | awk '{print $2}')
      if [ "$STATE" = "1" ]; then
        busctl --user set-property \
          org.gnome.Mutter.DisplayConfig \
          /org/gnome/Mutter/DisplayConfig \
          org.gnome.Mutter.DisplayConfig PowerSaveMode i 0
      else
        busctl --user set-property \
          org.gnome.Mutter.DisplayConfig \
          /org/gnome/Mutter/DisplayConfig \
          org.gnome.Mutter.DisplayConfig PowerSaveMode i 1
      fi
    '';
  };
in
{
  home.packages =
    extensionPkgs
    ++ [
      toggleScreen
    ]
    ++ (with pkgs; [
      blackbox-terminal
      gnome-tweaks
      seahorse
    ])
    ++ [
      pkgs.whitesur-gtk-theme
      pkgs.whitesur-icon-theme
    ];

  programs.chromium.extensions = [
    "gphhapmejobijbbhgpjhcjognlahblep" # GNOME Shell integration
  ];
  # Remove initial setup dialog
  home.file.".config/gnome-initial-setup-done".text = "yes";

  dconf.settings = lib.mkMerge [
    {
      "org/gnome/desktop/media-handling" = {
        automount = true;
        autorun-never = false;
        autorun-x-content-start-app = [ "x-content/unix-software" ];
      };
      # Do not sleep when ac power connected
      "org/gnome/settings-daemon/plugins/power" = {
        power-button-action = "nothing";
        sleep-inactive-ac-type = "nothing";
      };
      "org/gnome/desktop/wm/keybindings" = {
        switch-to-workspace-right = [ "<Control><Super>Right" ];
        switch-to-workspace-left = [ "<Control><Super>Left" ];
        move-to-workspace-right = [ "<Control><Shift><Super>Right" ];
        move-to-workspace-left = [ "<Control><Shift><Super>Left" ];
        switch-input-source =
          if imFramework == "ibus" then
            [
              "<Control>space"
            ]
          else
            [ ];
        switch-input-source-backward = [ ];
      };
      "org/gnome/settings-daemon/plugins/media-keys" = {
        control-center = [ ];
        control-center-static = [ ];
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/toggle-screen/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = mkString "NEXT";
        # https://www.reddit.com/r/gnome/comments/wencxw/almost_solved_i_wish_gnome_would_have_a_way_to/
        command = mkString "dbus-send --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:true";
        name = mkString "Power off monitor";
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/toggle-screen" = {
        binding = mkString "XF86PowerOff";
        # Nix store path — no escaping issues.
        command = mkString "${toggleScreen}/bin/gnome-toggle-screen";
        name = mkString "Toggle Screen (Power Key)";
      };
      "org/gnome/settings-daemon/plugins/housekeeping" = {
        donation-reminder-enabled = false;
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (p: p.extensionUuid) extensionPkgs;
        disabled-extensions = [ ];
        # disable-extension-version-validation = true;
        last-selected-power-profile = "performance";
        favorite-apps = lib.mkBefore [
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
          "firefox.desktop"
          "chromium-browser.desktop"
          "chromium.desktop"
          "gnome-system-monitor.desktop"
          "code.desktop"
          "steam-hidpi.desktop"
        ];
        welcome-dialog-last-shown-version = "43.1";
      };
      "org/gnome/mutter" = {
        # Active Screen Edges
        # Drag windows against screen edges to resize them
        edge-tiling = true;
        dynamic-workspaces = true;
        center-new-windows = true;
        experimental-features = [
          "scale-monitor-framebuffer"
          "variable-refresh-rate"
          "xwayland-native-scaling"
        ];
      };
      "org/gnome/desktop/interface" = {
        # scaling-factor = 1.0 * config.wayland.dpi / 96;
        # text-scaling-factor = mkDouble 1.5;

        # gtk-theme = "adw-gtk3";
        # cursor-theme = "capitaine-cursors";
        # cursor-size = 36 * config.wayland.dpi / 96;
        clock-show-weekday = true;
        show-battery-percentage = true;
        locate-pointer = true;
        enable-hot-corners = false;
      };
      "org/gnome/desktop/peripherals/keyboard" = {
        numlock-state = true;
      };
      "org/gnome/desktop/input-sources" = {
        sources =
          mkArray
            (type.tupleOf [
              type.string
              type.string
            ])
            [
              (mkTuple [
                (mkString "ibus")
                (mkString "rime")
              ])
            ];
        per-window = false;
        xkb-options = mkArray type.string [ "caps:swapescape" ];
      };

      "org/gnome/shell/extensions/system-monitor" = {
        memory-display = false;
      };
      "org/gnome/desktop/wm/preferences" = {
        action-middle-click-titlebar = "lower";
        focus-new-windows = "smart";
      };
      "org/gnome/system/location" = {
        enabled = true;
      };
      # just use the standard touchpad and mouse speed
      "org/gnome/desktop/peripherals/mouse" = {
        speed = 0;
      };
      "org/gnome/desktop/peripherals/touchpad" = {
        speed = 0;
        natural-scroll = true;
        tap-to-click = true;
      };
      "org/gnome/desktop/calendar" = {
        show-weekdate = true;
      };
      "org/gnome/shell/extensions/dash-to-dock" = {
        apply-custom-theme = true;
        custom-theme-shrink = true;
        # dash-max-icon-size = 48 * config.wayland.dpi / 96;
        show-mounts = false;
        click-action = "focus-or-appspread";
        scroll-action = "switch-workspace";
        autohide = true;
        dock-fixed = false;
        intellihide = false;
        intellihide-mode = "ALL_WINDOWS";
        show-dock-urgent-notify = false;
        show-trash = false;
      };
      "org/gnome/shell/extensions/user-theme" = {
        name = "WhiteSur-Light";
      };
      # Enable blur-my-shell for premium transparent top bar
      "org/gnome/shell/extensions/blur-my-shell/panel" = {
        blur = true;
        brightness = 0.9;
        sigma = 30;
      };
      # Keep popup colors and rounded backgrounds supplied by the theme.
      "org/gnome/shell/extensions/blur-my-shell/popup" = {
        blur = false;
      };
      "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
        blur = false;
      };
      "org/gnome/shell/extensions/kimpanel" = {
        font = "LXGW WenKai 26";
      };
      "org/gnome/Console" = {
        theme = "auto";
      };
      "ca/desrt/dconf-editor" = {
        show-warning = false;
      };
      "org/gnome/desktop/background" = {
        picture-uri = "file://${pkgs.wallpaper}/wallpaper.jpg";
        picture-uri-dark = "file://${pkgs.wallpaper}/wallpaper.jpg";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "org/gnome/desktop/screensaver" = {
        picture-uri = "file://${pkgs.wallpaper}/wallpaper.jpg";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "com/raggesilver/BlackBox" = {
        terminal-padding = mkTuple [
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
        ];
        # font = "monospace ${toString (10 * config.wayland.dpi / 96)}";
        theme-light = "Tomorrow";
        theme-dark = "Tomorrow Night";
        show-menu-button = false;
      };
    }
  ];

  home.activation.allowGdmReadFace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.acl}/bin/setfacl --modify=group:gdm:--x "$HOME" || true
  '';

  gtk = {
    enable = true;
    theme = {
      name = "WhiteSur-Light-solid";
      package = pkgs.whitesur-gtk-theme;
    };
    iconTheme = {
      name = "WhiteSur-light";
      package = pkgs.whitesur-icon-theme;
    };
    cursorTheme = {
      name = "capitaine-cursors-white";
      package = pkgs.capitaine-cursors;
    };
    gtk3.bookmarks = [
      "file://${config.home.homeDirectory}/.local/XDG/Desktop 桌面"
      "file://${config.home.homeDirectory}/.local/XDG/Documents"
      "file://${config.home.homeDirectory}/.local/XDG/Downloads"
      "file://${config.home.homeDirectory}/.local/XDG/Music"
      "file://${config.home.homeDirectory}/.local/XDG/Pictures"
      "file://${config.home.homeDirectory}/.local/XDG/Videos"
      "file://${config.home.homeDirectory}/Storage/BottlesShare Bottles 共享目录"
    ];
  };
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };
  home.sessionVariables = {
    # QT_STYLE_OVERRIDE = lib.mkForce "kvantum";
    XCURSOR_THEME = config.dconf.settings."org/gnome/desktop/interface".cursor-theme;
    # Wayland variables
    CLUTTER_BACKEND = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    # QT_QPA_PLATFORM = "wayland;xcb";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  ## Create startwm.sh for XRDP
  home.file."startwm.sh".text = ''
    #!/usr/bin/env bash
    export DESKTOP_SESSION="gnome"
    export GDMSESSION="gnome"
    export XDG_CURRENT_DESKTOP="GNOME"
    export XDG_SESSION_DESKTOP="gnome"
    dbus-run-session -- gnome-shell
  '';
  home.file."startwm.sh".executable = true;

  home.global-persistence = {
    directories = [
      ".config/gsconnect"
      ".local/share/keyrings"
    ];
  };
  # Override GNOME's IBus systemd service to use kimpanel-ibus-panel.
  # GNOME's built-in unit hardcodes "--panel disable", which bypasses the
  # NixOS ibus.panel option entirely. kimpanel-ibus-panel bridges IBus to the
  # kimpanel@kde.org GNOME Shell extension (which runs inside GNOME Shell and
  # can correctly position candidate popups on Wayland).
  systemd.user.services."org.freedesktop.IBus.session.GNOME" = lib.mkForce {
    Unit = {
      Description = "IBus Daemon for GNOME (kimpanel)";
      CollectMode = "inactive-or-failed";
      Requisite = [ "gnome-session-initialized.target" ];
      After = [ "gnome-session-initialized.target" ];
      PartOf = [ "gnome-session-initialized.target" ];
      Before = [ "gnome-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "org.freedesktop.IBus";
      ExecStart = [
        "${pkgs.bash}/bin/bash -c 'exec /run/current-system/sw/bin/ibus-daemon --panel ${pkgs.kdePackages.plasma-desktop}/libexec/kimpanel-ibus-panel $([ \"$XDG_SESSION_TYPE\" = \"x11\" ] && echo \"--xim\")'"
      ];
      Restart = "on-abnormal";
      TimeoutStopSec = 5;
      Slice = "session.slice";
    };
    Install = {
      WantedBy = [ "gnome-session.target" ];
    };
  };

  systemd.user.services.gsconnect-magicdns-poll = lib.mkIf (gsconnectDomains != [ ]) {
    Unit = {
      Description = "Poll GSConnect devices via Tailscale MagicDNS";
      After = [ "network.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart =
        let
          domainsStr = builtins.concatStringsSep " " (map (d: "\"${d}\"") gsconnectDomains);
          domainCount = builtins.length gsconnectDomains;
          parseAwk = pkgs.writeText "parse-devices.awk" ''
            BEGIN { RS = "objectpath [^/]+/org/gnome/Shell/Extensions/GSConnect/Device/"; }
            NR > 1 {
              match($0, /^[a-zA-Z0-9_-]+/);
              dev = substr($0, RSTART, RLENGTH);
              conn = ($0 ~ /Connected.*<true>/) ? "true" : "false";
              pair = ($0 ~ /Paired.*<true>/) ? "true" : "false";
              if (length(dev) > 0) print dev, conn, pair;
            }
          '';
        in
        "${pkgs.writeShellScript "gsconnect-poll" ''
          export PATH="${
            lib.makeBinPath (
              with pkgs;
              [
                coreutils
                gawk
                glib
                tailscale
              ]
            )
          }:$PATH"

          RUNDIR="''${XDG_RUNTIME_DIR:-/tmp}/gsconnect-helper"
          mkdir -p "$RUNDIR"

          # 1. 快速检查：GSConnect 扩展是否运行（若未启动则在 5ms 内秒退）
          gdbus introspect --session \
            --dest org.gnome.Shell.Extensions.GSConnect \
            --object-path /org/gnome/Shell/Extensions/GSConnect >/dev/null 2>&1 || exit 0

          # 2. 一次性获取所有设备状态
          get_devices_status() {
            gdbus call --session \
              --dest org.gnome.Shell.Extensions.GSConnect \
              --object-path /org/gnome/Shell/Extensions/GSConnect \
              --method org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
            gawk -f ${parseAwk}
          }

          # 3. 快速通道 (Fast Path)：如果所有配置的设备都已正常连接，直接退出（零开销，<25ms）
          CONNECTED_COUNT=0
          DISCONNECTED_COUNT=0
          while read -r dev conn pair; do
            [ -z "$dev" ] && continue
            if [ "$conn" = "true" ]; then
              CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
              rm -f "$RUNDIR/fail-$dev"
            else
              DISCONNECTED_COUNT=$((DISCONNECTED_COUNT + 1))
            fi
          done < <(get_devices_status)

          if [ "$CONNECTED_COUNT" -ge ${toString domainCount} ] && [ "$DISCONNECTED_COUNT" -eq 0 ]; then
            exit 0
          fi

          # 4. 辅助函数：带缓存的 IP 解析（避免每分钟反复执行 tailscale 命令）
          get_ip() {
            local d="$1"
            local cache="$RUNDIR/ip-$d"
            if [ -f "$cache" ]; then
              cat "$cache"
              return
            fi
            local ip
            ip=$(tailscale ip -4 "$d" 2>/dev/null || true)
            if [ -n "$ip" ]; then
              echo "$ip" > "$cache"
              echo "$ip"
            fi
          }

          # 5. 向尚未在线或未连通的目标发送发现包
          NEED_WAIT=false
          for domain in ${domainsStr}; do
            ip=$(get_ip "$domain")
            if [ -n "$ip" ]; then
              gdbus call --session \
                --dest org.gnome.Shell.Extensions.GSConnect \
                --object-path /org/gnome/Shell/Extensions/GSConnect \
                --method org.gtk.Actions.Activate "connect" "[<'lan://''${ip}:1716'>]" "{}" >/dev/null 2>&1 || true
              NEED_WAIT=true
            fi
          done

          [ "$NEED_WAIT" = "false" ] && exit 0

          # 6. 等待握手建连（放宽至 3 秒以适应 800ms+ 的 DERP 中继延迟）
          sleep 3

          # 7. 再次扫描设备并进行自动配对与死锁自愈
          while read -r dev conn pair; do
            [ -z "$dev" ] && continue

            # 情况 A：在线且未配对 -> 自动发起配对（带 10 分钟防骚扰冷却锁）
            if [ "$conn" = "true" ] && [ "$pair" = "false" ]; then
              LOCKFILE="$RUNDIR/pair-$dev.lock"
              NOW=$(date +%s)
              LAST_TRY=$(cat "$LOCKFILE" 2>/dev/null || echo 0)
              if [ $((NOW - LAST_TRY)) -gt 600 ]; then
                echo "$NOW" > "$LOCKFILE"
                gdbus call --session \
                  --dest org.gnome.Shell.Extensions.GSConnect \
                  --object-path "/org/gnome/Shell/Extensions/GSConnect/Device/$dev" \
                  --method org.gtk.Actions.Activate "pair" "[]" "{}" >/dev/null 2>&1 || true
              fi

            # 情况 B：成功连接且已配对 -> 清除失败与重试标记
            elif [ "$conn" = "true" ] && [ "$pair" = "true" ]; then
              rm -f "$RUNDIR/fail-$dev" "$RUNDIR/pair-$dev.lock"

            # 情况 C：电脑记录已配对但连接断开 -> 检测是否发生两端证书不同步死锁
            elif [ "$conn" = "false" ] && [ "$pair" = "true" ]; then
              FAIL_FILE="$RUNDIR/fail-$dev"
              count=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
              count=$((count + 1))
              echo "$count" > "$FAIL_FILE"

              # 连续 5 次轮询（约 5 分钟）持续断连时，检测对端 1716 端口是否其实活跃
              if [ "$count" -ge 5 ]; then
                DEADLOCK=false
                for domain in ${domainsStr}; do
                  ip=$(get_ip "$domain")
                  if [ -n "$ip" ] && timeout 1 bash -c "</dev/tcp/$ip/1716" 2>/dev/null; then
                    DEADLOCK=true
                    break
                  fi
                done

                # 如果对端 1716 端口存活但持续握手失败断连，说明手机端配对凭据已重置
                # 自动在后台解除失效配对，以便后续能够自动发起全新配对请求
                if [ "$DEADLOCK" = "true" ]; then
                  gdbus call --session \
                    --dest org.gnome.Shell.Extensions.GSConnect \
                    --object-path "/org/gnome/Shell/Extensions/GSConnect/Device/$dev" \
                    --method org.gtk.Actions.Activate "unpair" "[]" "{}" >/dev/null 2>&1 || true
                  rm -f "$FAIL_FILE"
                fi
              fi
            fi
          done < <(get_devices_status)
        ''}";
    };
  };

  systemd.user.timers.gsconnect-magicdns-poll = lib.mkIf (gsconnectDomains != [ ]) {
    Unit = {
      Description = "Poll GSConnect devices via Tailscale MagicDNS";
    };
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "1m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # 开机/登录时自动将音量设为 0（等待 WirePlumber 和默认声卡就绪）
  systemd.user.services.reset-volume-on-login = {
    Unit = {
      Description = "Reset audio volume to 0 on login";
      After = [ "wireplumber.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "reset-volume-zero" ''
        for i in $(seq 1 30); do
          if ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 0 2>/dev/null; then
            exit 0
          fi
          sleep 0.2
        done
      ''}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
