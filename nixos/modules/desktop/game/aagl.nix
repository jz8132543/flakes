{ inputs, pkgs, ... }:
let
  aaglPkg = inputs.aagl.packages.${pkgs.system}.anime-game-launcher;
in
{
  imports = [ inputs.aagl.nixosModules.default ];

  # 启用原神专属启动器 (An Anime Game Launcher)
  programs.anime-game-launcher = {
    enable = true;
    # 包装启动脚本：在 steam-run (Bubblewrap) 容器内先将 /tmp/.X11-unix 赋权为 1777，
    # 解决 Gamescope 内部 Xwayland 因目录权限不是 1777 导致的:
    # "wlserver: /tmp/.X11-unix not owned by root or us" 及启动失败问题。
    package = pkgs.symlinkJoin {
      name = "anime-game-launcher-wrapped";
      paths = [
        (pkgs.writeShellScriptBin "anime-game-launcher" ''
          ${pkgs.steam-run}/bin/steam-run bash -c 'chmod 1777 /tmp/.X11-unix 2>/dev/null || true; exec "${aaglPkg.unwrapped}/bin/anime-game-launcher" "$@"' -- "$@"
        '')
        aaglPkg
      ];
    };
  };

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
