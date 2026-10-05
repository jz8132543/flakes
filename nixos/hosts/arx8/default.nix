{
  config,
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
      nixosModules.optimize.fakehttp
      nixosModules.optimize.network-desktop
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.optimize.dev
      # nixosModules.services.microsocks
    ];

  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
  ];
  desktop.nvidia = {
    mode = "offload";
  };
  desktop.winapps = {
    kvm = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = false;
    };
    docker = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = false;
    };
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
    ];
  };

  # 自动创建 Steam 共享库及原神共享目录，保证权限归属 tippy:users
  systemd.tmpfiles.rules = [
    "d /mnt/games 0755 tippy users -"
    "d /mnt/games/SteamLibrary 0775 tippy users -"
    "d /mnt/games/SteamLibrary/steamapps 0775 tippy users -"
    "d /mnt/games/SteamLibrary/steamapps/common 0775 tippy users -"
    "d '/mnt/games/Genshin Impact Game' 0755 tippy users -"
    "d /mnt/games/.temp 0755 tippy users -"
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
