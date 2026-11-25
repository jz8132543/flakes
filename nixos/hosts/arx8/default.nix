{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.networking.dn42.mesh
      nixosModules.optimize.network-desktop
      nixosModules.optimize.brutal
      nixosModules.services.traefik
      nixosModules.optimize.dev
      # nixosModules.services.microsocks
    ]
    ++ nixosModules.services."ai-local".all;

  optimize.brutal.target = "!cn";

  services.duet.enable = true;
  services.local-llm.workbench.enable = true;
  services.paseo.enable = true;

  services.local-llm.settings.strata = {
    enable = true;
    family = "qwen";
    model = "IQ3_XXS";
    context = "32768";
    parallel = 1;
    vision = "no";
    lowRam = "mmap";
    source = "huggingface";
    downloadProxy = "http://127.0.0.1:7890";
    port = config.ports.strata;
    dataDir = "/mnt/games/AI/strata";
  };

  # The compositor owns scaling; keep client font DPI at its unscaled default.
  home-manager.users.tippy.wayland.dpi = 96;
  home-manager.users.tippy.programs.umbriel.settings.general.xwayland_native_resolution = true;
  services.displayManager.noctalia-greeter.settings.output = {
    scales = "eDP-1:1.5";
    use_synced_settings = false;
  };
  home-manager.users.tippy.programs.umbriel.settings.output."eDP-1" = {
    # Measured from this host's active display; other outputs retain auto detection.
    mode = "2560x1600@240";
    scale = 1.5;
    hdr = "on";
    workspaces = 4;
  };
  # Keep the SDR background available until the HDR client commits its first frame.
  home-manager.users.tippy.programs.noctalia.settings.wallpaper.enabled =
    lib.mkIf config.desktop.umbriel.enable true;
  home-manager.users.tippy.systemd.user.services.hdr-wallpaper =
    lib.mkIf config.desktop.umbriel.enable
      {
        Unit = {
          Description = "Static BT.2020/PQ HDR wallpaper";
          After = [
            "umbriel.service"
            "umbriel-session.target"
            "noctalia.service"
          ];
          Wants = [ "noctalia.service" ];
          PartOf = [ "umbriel-session.target" ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          TimeoutStartSec = 30;
          ExecStart = "${pkgs.hdr-wallpaper}/bin/hdr-wallpaper eDP-1 ${pkgs.wallpaper.hdr}/wallpaper-hdr.png";
          ExecStartPost = "${config.programs.noctalia.package}/bin/noctalia msg config-set wallpaper.enabled false";
          ExecStopPost = "-${config.programs.noctalia.package}/bin/noctalia msg config-set wallpaper.enabled true";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "umbriel-session.target" ];
      };
  home-manager.users.tippy.programs.noctalia.settings.lockscreen_widgets =
    let
      placement = {
        placement_width = 1706.0;
        placement_height = 1066.0;
      };
    in
    {
      widget_order = [
        "lock-cpu"
        "lock-network"
        "lock-ram"
        "lock-clock"
        "lock-calendar"
        "lockscreen-login-box@eDP-1"
      ];
      widget.lock-cpu = placement // {
        cx = 317.0;
        cy = 289.0;
        box_width = 336.0;
        box_height = 220.0;
      };
      widget.lock-network = placement // {
        cx = 317.0;
        cy = 533.0;
        box_width = 336.0;
        box_height = 220.0;
      };
      widget.lock-ram = placement // {
        cx = 317.0;
        cy = 777.0;
        box_width = 336.0;
        box_height = 220.0;
      };
      widget.lock-clock = placement // {
        cx = 853.0;
        cy = 533.0;
        box_width = 672.0;
        box_height = 708.0;
        settings.background_opacity = 0.38;
      };
      widget.lock-calendar = placement // {
        cx = 1389.0;
        cy = 533.0;
        box_width = 336.0;
        box_height = 708.0;
      };
      widget."lockscreen-login-box@eDP-1" = placement // {
        type = "login_box";
        output = "eDP-1";
        cx = 853.0;
        cy = 815.0;
        box_width = 608.0;
        box_height = 80.0;
        settings = {
          layout = "compact";
          show_session_buttons = false;
          show_media = false;
          show_media_controls = false;
          show_weather = false;
          show_login_button = false;
          show_password_reveal = false;
          show_unlock_hint = false;
          show_caps_lock = false;
          show_keyboard_layout = false;
          center_password_text = true;
          background_color = "surface_container";
          background_opacity = 0.0;
          background_radius = 24.0;
          input_opacity = 0.25;
          input_radius = 16.0;
        };
      };
    };
  # Noctalia uses nonblocking swaps; forced NVIDIA vblank stalls its Wayland event loop.
  systemd.user.services.noctalia = lib.mkIf config.desktop.noctalia.enable {
    environment.__GL_SYNC_TO_VBLANK = "0";
  };

  services.mihomo.routing.proxyPublicSsh = true;
  mihomoKernel = "mihomo-smart";
  services.mihomo.subscription = {
    enable = true;
    urlFile = config.sops.templates."mihomo/subscription-url".path;
  };
  sops.secrets."xray/subscription_path_token" = { };
  sops.templates."mihomo/subscription-url" = {
    mode = "0400";
    content = "https://sub.${config.networking.domain}/${
      config.sops.placeholder."xray/subscription_path_token"
    }/mihomo-smart.yaml";
  };

  programs.winpodx.activation.method = "mas";
  # XWayland exposes twice GNOME's logical size on this HiDPI display.
  programs.winpodx.dpi = 200;

  # 保持与当前运行环境一致的稳定 7.2 内核，避免 7.3 上游未签名外部模块 cer 报错
  boot.kernelPackages = pkgs.linuxPackages;

  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
    (bitwig-studio.override { applyJarPatch = true; })
  ];
  desktop.nvidia = {
    mode = "offload";
  };

  # services.create_ap = {
  #   enable = true;
  #   settings = {
  #     INTERNET_IFACE = "wlp4s0";
  #     WIFI_IFACE = "wlp4s0";
  #     SSID = "ARX8";
  #     PASSPHRASE = "qwertyut";
  #     # HIDDEN = 1;
  #     IEEE80211AX = 1;
  #     FREQ_BAND = 5;
  #   };
  # };
  # };

  # ============================================================================
  # ARX8 专用配置：第二块 2TB 磁盘 (Windows D盘) 挂载与游戏目录设置
  # ============================================================================
  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-label/GAMES";
    fsType = "btrfs";
    options = [
      "defaults"
      "compress=zstd:1"
      "noatime"
      "discard=async"
      "space_cache=v2"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=5s"
    ];
  };

  # 自动创建 Steam 共享库及原神共享目录，保证权限归属 tippy:users 并开放给 Windows (0777)
  systemd.tmpfiles.rules = [
    "d /mnt/games 0777 tippy users -"
    "d /mnt/games/SteamLibrary 0777 tippy users -"
    "d /mnt/games/SteamLibrary/steamapps 0777 tippy users -"
    "d /mnt/games/SteamLibrary/steamapps/common 0777 tippy users -"
    "d '/mnt/games/Genshin Impact Game' 0777 tippy users -"
    "d /mnt/games/.temp 0777 tippy users -"
  ];

  # 将第二块游戏磁盘纳入系统月度 Btrfs 数据校验
  services.btrfs.autoScrub.fileSystems = [
    config.fileSystems."/nix".device
    "/mnt/games"
  ];

  # 声明式将原神（AAGL）的安装目录与下载缓存固定在 D 盘 (/mnt/games)
  system.activationScripts.set-genshin-game-path = {
    deps = [ "users" ];
    text = ''
            CFG_DIR="/persist/home/tippy/.local/share/anime-game-launcher"
            mkdir -p "$CFG_DIR"
            CFG_FILE="$CFG_DIR/config.json"
            if [ -f "$CFG_FILE" ]; then
              ${pkgs.jq}/bin/jq '
                .game.path.china = "/mnt/games/Genshin Impact Game" |
                .game.path.global = "/mnt/games/Genshin Impact Game" |
                .launcher.temp = "/mnt/games/.temp" |
                .game.wine.shared_libraries.wine = false |
                .game.wine.shared_libraries.gstreamer = false |
                .game.wine.winewayland = false
              ' "$CFG_FILE" > "$CFG_FILE.tmp" && mv "$CFG_FILE.tmp" "$CFG_FILE"
            else
              cat << 'EOF' > "$CFG_FILE"
      {
        "launcher": {
          "temp": "/mnt/games/.temp"
        },
        "game": {
          "path": {
            "global": "/mnt/games/Genshin Impact Game",
            "china": "/mnt/games/Genshin Impact Game"
          },
          "wine": {
            "language": "System",
            "winewayland": false,
            "shared_libraries": {
              "wine": false,
              "gstreamer": false
            }
          },
          "enhancements": {
            "gamescope": {
              "enabled": false
            }
          }
        }
      }
      EOF
            fi

            # 建立软链接作为双重保障（即使启动器重置为默认目录名，也直通第二块磁盘）
            if [ -d "$CFG_DIR/YuanShen" ] && [ ! -L "$CFG_DIR/YuanShen" ]; then
              rmdir "$CFG_DIR/YuanShen" 2>/dev/null || true
            fi
            if [ -d "$CFG_DIR/Genshin Impact" ] && [ ! -L "$CFG_DIR/Genshin Impact" ]; then
              rmdir "$CFG_DIR/Genshin Impact" 2>/dev/null || true
            fi
            ln -sfn "/mnt/games/Genshin Impact Game" "$CFG_DIR/YuanShen"
            ln -sfn "/mnt/games/Genshin Impact Game" "$CFG_DIR/Genshin Impact"
            ln -sfn "/mnt/games/.temp" "$CFG_DIR/temp"

            chown -hR tippy:users "$CFG_DIR"
    '';
  };
}
