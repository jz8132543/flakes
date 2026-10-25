{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:

let
  cfg = config.programs.winapps;
  # 根据 DPI 计算缩放
  sysCfg = lib.attrByPath [ "programs" "winapps" ] { } osConfig;
  podmanEnabled = sysCfg.podman.enable or false;
  winappsPackage =
    sysCfg.package or inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps;
  # 复用 NixOS 模块生成的 compose 文件（/etc/winapps/compose.yaml 指向同一 store 路径）
  composeYaml = lib.attrByPath [ "environment" "etc" "winapps/compose.yaml" "source" ] null osConfig;

  winappsDiscoverScript = pkgs.writeShellScript "winapps-discover" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.podman
        pkgs.podman-compose
        pkgs.slirp4netns
        pkgs.procps
        pkgs.util-linux
        pkgs.coreutils
      ]
    }:/run/wrappers/bin:$PATH

    state="$(podman inspect --format '{{.State.Status}}' WinApps 2>/dev/null || true)"
    case "$state" in
      running) ;;
      paused)
        # Only the 'winapps' client resumes a paused container, so the
        # installer has to do it before it can query applications.
        podman-compose --file "$HOME/.config/winapps/compose.yaml" unpause >/dev/null
        # A resumed guest needs time before its RDP stack answers; a
        # plain TCP check is not enough because rootlessport accepts early.
        rdp_port="${toString (sysCfg.podman.port or 3390)}"
        for _ in $(seq 60); do
          if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'"$rdp_port"' && echo -ne "\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00" >&3 && head -c 1 <&3' >/dev/null 2>&1; then
            break
          fi
          sleep 5
        done
        ;;
      *) exit 0 ;;
    esac

    pgrep -u "$UID" -f '(^|/)(xfreerdp|sdl-freerdp|wlfreerdp)( |$)' >/dev/null && exit 0

    exec 9>"$XDG_RUNTIME_DIR/winapps-discovery.lock"
    flock -n 9 || exit 0

    # --add-apps runs both the officially supported and the generic
    # detected-application flows, so user-installed apps are picked up too.
    ${winappsPackage}/bin/winapps-setup --user --add-apps
    ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications"
  '';
in
{
  options.programs.winapps = {
    enable = lib.mkEnableOption "WinApps Desktop Client and Autopause configuration" // {
      default = sysCfg.enable or true;
    };
    windowsScale = lib.mkOption {
      type = lib.types.ints.positive;
      default = sysCfg.windows.scale or 150;
      description = "DPI scale percentage for full Windows desktop session (winapps windows). Default is 150.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 声明式 winapps.conf（全部使用 WinApps 官方配置项）
    home.file.".config/winapps/winapps.conf".text = ''
      # ==============================================================================
      # WINAPPS CONFIGURATION (NixOS Managed)
      # ==============================================================================
      RDP_USER=${builtins.toJSON (sysCfg.podman.username or "Docker")}
      RDP_PASS=${builtins.toJSON (sysCfg.podman.password or "admin")}
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_PORT="${toString (sysCfg.podman.port or 3390)}"
      WAFLAVOR="podman"
      FREERDP_COMMAND="xfreerdp"

      # Use 100% scale to avoid XWayland X_PutImage BadMatch crashes with FreeRDP 3
      RDP_SCALE="100"

      # 专门针对 Windows 完整桌面会话 (winapps windows) 的参数：
      # 上游 winapps 在运行 windows 时会自动追加 RDP_FLAGS_WINDOWS。
      # RemoteApp 保持 100% 缩放以避免 XWayland BadMatch 崩溃；
      # 完整桌面通过 /scale-desktop 启用 Windows 服务端高 DPI 缩放，彻底解决 2.5K/4K 屏幕上字小看不清的问题。
      RDP_FLAGS_WINDOWS="/scale-desktop:${toString cfg.windowsScale} /scale-device:140"

      # 可移动介质挂载路径（GNOME/udisks 默认使用 /run/media）
      REMOVABLE_MEDIA="/run/media"

      # 驱动重定向：挂载家目录为 \tsclient\home，
      # 共享文件夹为 \tsclient\WinAppsShare，并启用打印机/剪贴板/声卡重定向
      # - /network:lan: 本机回环低延迟模式
      # FreeRDP 3 rejects the legacy /gfx-progressive and +glyph-cache flags.
      # 禁用自动重连并设置最大重试为 0，防止断开时在桌面上反复闪烁弹窗抢占焦点
      RDP_FLAGS="/cert:tofu /network:lan /sound /microphone +clipboard /printer /drive:home,${config.home.homeDirectory} /drive:WinAppsShare,${
        sysCfg.podman.sharedPath or "${config.home.homeDirectory}/Storage/WinAppsShare"
      } /auto-reconnect-max-retries:0 -auto-reconnect"

      DEBUG="true"

      # ==============================================================================
      # [官方闲置自动挂起 (AUTOPAUSE)]
      # ==============================================================================
      # 当所有 Office/Windows 窗口关闭 300 秒后，WinApps 会自动通过
      # podman-compose pause 将容器置入 pause 状态，CPU 占用彻底降为 0%；
      # 下次打开 docx/xlsx/pptx 等文件时会自动 unpause 秒级恢复。
      AUTOPAUSE="${if sysCfg.autopause.enable or true then "on" else "off"}"
      AUTOPAUSE_TIME="${toString (sysCfg.autopause.timeout or 300)}"
      RDP_TIMEOUT="120"
      APP_SCAN_TIMEOUT="180"
    '';

    # 2. 与 NixOS 模块生成的开机启动服务共用同一个 compose 文件，
    # 使 WinApps 官方的 pause/unpause/start 操作命中同一个容器
    home.file.".config/winapps/compose.yaml" = lib.mkIf (podmanEnabled && composeYaml != null) {
      source = composeYaml;
    };

    # Upstream setup writes app metadata and icons here. Never link this mutable
    # directory to the read-only Nix store. Preserve only a legacy store symlink.
    home.activation.winappsWritableApps = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      apps="$HOME/.local/share/winapps/apps"
      if [ -L "$apps" ]; then
        case "$(${pkgs.coreutils}/bin/readlink -f "$apps")" in
          /nix/store/*/src/apps)
            run ${pkgs.coreutils}/bin/mv --backup=numbered "$apps" "$apps.legacy-link"
            ;;
          *) echo "WinApps: leaving custom apps symlink unchanged" ;;
        esac
      fi
      run ${pkgs.coreutils}/bin/mkdir -p "$apps" "$HOME/.local/bin"
    '';

    home.global-persistence.directories = [
      "Storage/WinApps"
      "Storage/WinAppsShare"
      ".local/bin"
      ".local/share/winapps"
      ".local/share/applications"
      ".config/freerdp"
    ];

    # Bootstrap entries use upstream's actual Click-to-Run definitions. The
    # official scanner creates these same IDs, including other installed apps.
    xdg.desktopEntries = {
      word-o365 = {
        name = "Microsoft Word";
        genericName = "Word Processor";
        comment = "Microsoft Word (WinApps)";
        exec = "${winappsPackage}/bin/winapps word-o365 %F";
        icon = "${winappsPackage}/src/apps/word-o365/icon.svg";
        terminal = false;
        categories = [
          "Office"
          "WordProcessor"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          "application/msword"
          "application/vnd.ms-word.document.macroEnabled.12"
          "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
          "application/vnd.ms-word"
          "application/msword-template"
          "application/x-msword"
          "application/rtf"
        ];
      };
      excel-o365 = {
        name = "Microsoft Excel";
        genericName = "Spreadsheet";
        comment = "Microsoft Excel (WinApps)";
        exec = "${winappsPackage}/bin/winapps excel-o365 %F";
        icon = "${winappsPackage}/src/apps/excel-o365/icon.svg";
        terminal = false;
        categories = [
          "Office"
          "Spreadsheet"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          "application/vnd.ms-excel"
          "application/msexcel"
          "application/x-msexcel"
          "text/csv"
        ];
      };
      powerpoint-o365 = {
        name = "Microsoft PowerPoint";
        genericName = "Presentation";
        comment = "Microsoft PowerPoint (WinApps)";
        exec = "${winappsPackage}/bin/winapps powerpoint-o365 %F";
        icon = "${winappsPackage}/src/apps/powerpoint-o365/icon.svg";
        terminal = false;
        categories = [
          "Office"
          "Presentation"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.presentationml.presentation"
          "application/vnd.ms-powerpoint"
          "application/mspowerpoint"
          "application/powerpoint"
        ];
      };
      windows = {
        name = "Windows Subsystem";
        genericName = "Virtual Desktop";
        comment = "Open Full Windows Desktop Session";
        exec = "${winappsPackage}/bin/winapps windows";
        icon = "${winappsPackage}/src/install/windows.svg";
        terminal = false;
        categories = [ "Utility" ];
      };

      winapps-scan = {
        name = "WinApps: Scan Applications";
        genericName = "Application Discovery";
        comment = "Scan Windows for newly installed applications (e.g. Doubao) and generate desktop entries";
        exec = "${pkgs.writeShellScript "trigger-winapps-scan" ''
          exec systemctl --user start winapps-discover.service
        ''}";
        icon = "system-software-install";
        terminal = false;
        categories = [ "Utility" ];
      };
    };

    # 4. 注册协议与文档格式默认关联 (docx, xlsx, pptx 等默认由 WinApps Office 打开)
    xdg.mimeApps.defaultApplications = {
      # Microsoft Word
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "word-o365.desktop";
      "application/msword" = "word-o365.desktop";
      "application/vnd.ms-word.document.macroEnabled.12" = "word-o365.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = "word-o365.desktop";
      "application/vnd.ms-word" = "word-o365.desktop";
      "application/rtf" = "word-o365.desktop";

      # Microsoft Excel
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "excel-o365.desktop";
      "application/vnd.ms-excel" = "excel-o365.desktop";
      "application/vnd.ms-excel.sheet.macroEnabled.12" = "excel-o365.desktop";
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = "excel-o365.desktop";
      "application/vnd.ms-excel.sheet.binary.macroenabled.12" = "excel-o365.desktop";

      # Microsoft PowerPoint
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" =
        "powerpoint-o365.desktop";
      "application/vnd.ms-powerpoint" = "powerpoint-o365.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.template" = "powerpoint-o365.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow" =
        "powerpoint-o365.desktop";

      # Protocol Handlers
      "x-scheme-handler/ms-word" = "ms-office-protocol-handler.desktop";
      "x-scheme-handler/ms-excel" = "ms-office-protocol-handler.desktop";
      "x-scheme-handler/ms-powerpoint" = "ms-office-protocol-handler.desktop";
    };

    # The official installer copies this handler into ~/.local/share/applications
    # itself. Declaring it here would symlink the same store file and break that copy.

    # This is a short periodic job, not an RDP polling daemon. Never wake a
    # paused VM or disconnect someone using Windows just to scan applications.
    systemd.user.services.winapps-discover =
      lib.mkIf (podmanEnabled && (sysCfg.discovery.enable or true))
        {
          Unit = {
            Description = "Discover Windows applications using the official WinApps installer";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            TimeoutStartSec = "8min";
            Environment = [ "WINAPPS_AUTO_DISCOVERY=1" ];
            ExecStart = "${winappsDiscoverScript}";
          };
        };

    # Manual command to trigger application discovery on demand.
    home.packages = lib.mkIf podmanEnabled [
      (pkgs.writeShellScriptBin "winapps-scan" ''
        if systemctl --user list-unit-files winapps-discover.service 2>/dev/null | grep -q winapps-discover; then
          echo "Starting WinApps application discovery service..."
          systemctl --user start winapps-discover.service
          echo "Discovery service triggered. Viewing logs (press Ctrl+C to exit log view):"
          journalctl --user -u winapps-discover.service -f
        else
          echo "Starting WinApps application discovery directly..."
          exec ${winappsDiscoverScript}
        fi
      '')
    ];

    # 5. WinApps Launcher 开机自启
    systemd.user.services.winapps-launcher = {
      Unit = {
        Description = "WinApps Taskbar Launcher Widget";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${
          inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps-launcher
        }/bin/winapps-launcher";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
