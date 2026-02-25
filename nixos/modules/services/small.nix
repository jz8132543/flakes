{
  lib,
  pkgs,
  ...
}:
{
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
