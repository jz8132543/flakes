{
  lib,
  pkgs,
  config,
  ...
}:
{
  # Btrfs 优化：显著降低 CPU 占用并优化磁盘空间
  # 1. 挂载优化：动态从 Disko 提取挂载点并应用参数，避免递归，减少 CPU 计算
  # fileSystems =
  #   let
  #     commonOptions = [
  #       "noatime"
  #       "compress=zstd:1" # 使用最低压缩级别以减少 CPU 负载
  #       "commit=120" # 延长提交间隔，减少元数据写入频率
  #       "discard=async" # 异步丢弃，降低写入高峰时的延迟
  #       "space_cache=v2" # 确保使用更高效的 v2 缓存
  #     ];
  #     # 从 disko 提取所有 btrfs 挂载点（安全地避开了对 config.fileSystems 的直接引用）
  #     btrfsMounts = lib.concatLists (
  #       lib.mapAttrsToList (
  #         _: disk:
  #         lib.concatLists (
  #           lib.mapAttrsToList (
  #             _: part:
  #             if part.content.type or "" == "btrfs" then
  #               lib.filter (m: m != null) (
  #                 lib.mapAttrsToList (_: subvol: subvol.mountpoint or null) (part.content.subvolumes or { })
  #               )
  #             else
  #               [ ]
  #           ) (disk.content.partitions or { })
  #         )
  #       ) config.disko.devices.disk
  #     );
  #   in
  #   lib.genAttrs btrfsMounts (mountpoint: {
  #     options = lib.mkForce (
  #       (
  #         if mountpoint == "/swap" then
  #           [
  #             "noatime"
  #             "nodiratime"
  #             "nodatacow"
  #           ]
  #         else
  #           commonOptions
  #       )
  #       ++ [ (if mountpoint == "/" then "subvol=rootfs" else "subvol=${lib.removePrefix "/" mountpoint}") ]
  #     );
  #   });

  # 2. 替代 utils.btrfsMixed：针对主分区追加 -M 参数实现全盘 mixed block groups
  disko.devices.disk.main.content.partitions.NIXOS.content.extraArgs = lib.mkAfter [ "-M" ];

  # 3. 服务优化：禁用耗费 CPU 的定期后台任务
  services.btrfs.autoScrub.enable = lib.mkForce false;

  # 1. 移除 Nix 注册表中的源码副本 (nixpkgs, home-manager 等)
  # 以及清理 NIX_PATH 引用，防止 200MB+ 的源码目录入镜像
  nix.registry = lib.mkForce { };
  nix.nixPath = lib.mkForce [ ];
  nix.settings.nix-path = lib.mkForce [ ];

  # 2. 彻底禁用所有文档、手册和帮助文件
  documentation = {
    enable = lib.mkForce false;
    man.enable = lib.mkForce false;
    doc.enable = lib.mkForce false;
    info.enable = lib.mkForce false;
    nixos.enable = lib.mkForce false;
  };

  # 3. 禁用不必要的硬件固件 (针对虚拟机优化)
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # 4. Nix 运行环境优化
  nix.settings = {
    keep-outputs = lib.mkForce false;
    keep-derivations = lib.mkForce false;
  };

  # 5. 精简 Initrd 内核模块
  # boot.initrd = {
  #   includeDefaultModules = lib.mkForce false;
  #   availableKernelModules = lib.mkForce [
  #     "virtio_net"
  #     "virtio_pci"
  #     "virtio_mmio"
  #     "virtio_blk"
  #     "virtio_scsi"
  #     "virtio_balloon"
  #     "virtio_console"
  #     "9p"
  #     "9pnet_virtio"
  #     "virtio_gpu"
  #     "virtio_rng"
  #     "ata_piix"
  #     "ahci"
  #     "sd_mod"
  #     "sr_mod"
  #     "btrfs"
  #     "vfat"
  #   ];
  # };

  # 6. 禁用 GUI 相关泄露
  fonts.fontconfig.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  xdg.icons.enable = lib.mkForce false;
  xdg.sounds.enable = lib.mkForce false;

  # 7. 强制替换重型工具为最小化版本 (Overlay 策略)
  programs.git.package = lib.mkForce pkgs.gitMinimal;
  # nixpkgs.overlays = [
  #   (_final: prev: {
  #     # 使用 Overlay 替换 curlFull 为基础级 curl
  #     curlFull = prev.curl;
  #     # 替换 gitFull 避免拉取 SVN/Python/Perl
  #     gitFull = prev.gitMinimal;
  #   })
  # ];

  # 8. 彻底移除系统级的 GTK/VTE 依赖
  # programs.bash.vteIntegration = lib.mkForce false;
  # programs.zsh.vteIntegration = lib.mkForce false;

  # 9. 移除非必要服务
  # 注意：禁用 fail2ban 会减少约 110MB (Python) 的体积，但会降低 SSH 安全性
  services.fail2ban.enable = lib.mkForce false;

  # 10. 极致精简 Shell 与核心工具 (目标 2GiB)
  # 禁用 Fish 以移除 Python 依赖 (110MB+)，切换主用户 Shell 到 Bash
  programs.fish.enable = lib.mkForce false;
  programs.zsh.enable = lib.mkForce false;
  users.users.tippy.shell = lib.mkForce pkgs.bash;

  # 禁用 Mosh 以移除 Perl 依赖 (57MB+)
  programs.mosh.enable = lib.mkForce false;

  # 移除 command-not-found 和内核交互工具
  programs.command-not-found.enable = lib.mkForce false;
  boot.enableContainers = lib.mkForce false;
  security.rtkit.enable = lib.mkForce false;
  services.bpftune.enable = lib.mkForce false;

  # 11. 移除 baseline-apps 中的非必要大包 (通过过滤)
  # environment.systemPackages = lib.mkForce [
  #   pkgs.curl
  #   pkgs.wget
  #   pkgs.tmux
  #   pkgs.htop # 替代 bottom
  #   pkgs.neovim
  #   pkgs.jq
  #   pkgs.ripgrep
  #   pkgs.fd
  #   pkgs.age
  # ];
}
