{ inputs, ... }:
{
  imports = [ inputs.aagl.nixosModules.default ];

  # 启用原神专属启动器 (An Anime Game Launcher)
  # AAGL 社区用代号 "An Anime Game" 代表原神，这是原神在 Linux 下唯一的正式专用启动器
  programs.anime-game-launcher.enable = true;

  # 全能版 anime-games-launcher 目前上游 registry 尚未收录原神，可按需保留或关闭
  programs.anime-games-launcher.enable = true;

  # 其余单体启动器保持关闭
  programs.honkers-railway-launcher.enable = false;
  programs.honkers-launcher.enable = false;
  programs.wavey-launcher.enable = false;
  programs.sleepy-launcher.enable = false;

  # 配置 AAGL 官方二进制缓存加速
  nix.settings = {
    substituters = [ "https://ezkea.cachix.org" ];
    trusted-public-keys = [ "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=" ];
  };

  # 配合持久化存储 (Impermanence)，确保重启后不丢失：
  # 1. 启动器登录与路径配置 (config.json)
  # 2. Wine Prefix (虚拟 C 盘环境、Windows 注册表及 AppData)
  # 3. 游戏运行器 (Wine/Proton GE runners、DXVK/VKD3D 组件)
  # 4. 米哈游官方登录凭证与 Token 缓存
  environment.global-persistence.user.directories = [
    ".local/share/anime-game-launcher"
    ".config/anime-game-launcher"
    ".local/share/anime-games-launcher"
    ".config/anime-games-launcher"
    ".local/share/an-anime-game-launcher"
    ".config/an-anime-game-launcher"
    ".local/share/miHoYo"
    ".local/share/Hoyoverse"
  ];
}
