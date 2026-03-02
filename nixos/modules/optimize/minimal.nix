{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.environment.minimal;
in
{
  config = lib.mkMerge [
    { environment.minimal = lib.mkDefault true; }
    (lib.mkIf cfg {
      # 1. 核心系统特性精简
      documentation = {
        enable = lib.mkForce false;
        man.enable = lib.mkForce false;
        doc.enable = lib.mkForce false;
        info.enable = lib.mkForce false;
        nixos.enable = lib.mkForce false;
      };

      # 2. Btrfs 额外优化 (联动 Disko 参数外的部分)
      services.btrfs.autoScrub.enable = lib.mkForce false;
      disko.devices.disk.main.content.partitions.NIXOS.content.extraArgs = lib.mkAfter [ "-M" ];

      # 3. 移除 Nix 注册表中的源码副本，减少磁盘占用
      nix.registry = lib.mkForce { };
      nix.nixPath = lib.mkForce [ ];
      nix.settings.nix-path = lib.mkForce [ ];

      # 4. Nix 运行环境优化
      nix.settings = {
        keep-outputs = lib.mkForce false;
        keep-derivations = lib.mkForce false;
      };

      # 5. 禁用不必要的硬件固件 (针对虚拟机优化)
      hardware.enableRedistributableFirmware = lib.mkForce false;

      # 6. 禁用 GUI 相关依赖与服务
      fonts.fontconfig.enable = lib.mkForce false;
      services.xserver.enable = lib.mkForce false;
      xdg.icons.enable = lib.mkForce false;
      xdg.sounds.enable = lib.mkForce false;

      # 7. 强制替换重型工具为最小化版本
      programs.git.package = lib.mkForce pkgs.gitMinimal;

      # 8. 移除非必要服务
      services.fail2ban.enable = lib.mkForce false;

      # 9. 精简 Shell 与核心工具，移除 Python/Perl 依赖
      programs.fish.enable = lib.mkForce false;
      programs.zsh.enable = lib.mkForce false;
      programs.mosh.enable = lib.mkForce false;
      programs.command-not-found.enable = lib.mkForce false;

      boot.enableContainers = lib.mkForce false;
      security.rtkit.enable = lib.mkForce false;
      services.bpftune.enable = lib.mkForce false;

      # 允许在使用 minimal 模式时禁用用户的默认 Shell
      users.users.tippy.ignoreShellProgramCheck = true;
    })
  ];
}
