{
  lib,
  config,
  pkgs,
  ...
}:
{
  # 1. 移除 Nix 注册表中的源码副本 (nixpkgs, home-manager 等)
  # 使其从网络获取而非占用本地 store 空间
  nix.registry = lib.mkForce { };

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

  # 4. Nix 构建性能与体积优化
  nix.settings = {
    # 禁用保留输出和中间产物，减少 store 扫描负担
    keep-outputs = lib.mkForce false;
    keep-derivations = lib.mkForce false;
  };

  # 5. 精简 Initrd 内核模块 (仅保留虚拟机必要的驱动)
  boot.initrd = {
    # 禁用默认的大量驱动集 (SATA, USB, HID 等)
    includeDefaultModules = lib.mkForce false;
    # 仅手动列出 VirtIO 和基础文件系统所需的模块
    availableKernelModules = lib.mkForce [
      "virtio_net"
      "virtio_pci"
      "virtio_mmio"
      "virtio_blk"
      "virtio_scsi"
      "virtio_balloon"
      "virtio_console"
      "9p"
      "9pnet_virtio"
      "virtio_gpu"
      "virtio_rng"
      # 部分云平台可能需要的基础控制器
      "ata_piix"
      "ahci"
      "sd_mod"
      "sr_mod"
      # 文件系统支持
      "btrfs"
      "vfat"
    ];
  };

  # 6. 禁用所有可能的 GUI 泄露
  fonts.fontconfig.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  xdg.icons.enable = lib.mkForce false;
  xdg.sounds.enable = lib.mkForce false;

  # 7. 进一步压缩 Zsh/Fish (关闭 VTE 集成以移除 GTK 依赖)
  # 注意：这需要 Home-Manager 端配合，但在 OS 层我们可以禁用 VTE 环境
  programs.bash.vteIntegration = lib.mkForce false;
  programs.zsh.vteIntegration = lib.mkForce false;

  # 8. 移除不必要的系统功能
  programs.command-not-found.enable = lib.mkForce false;
  boot.enableContainers = lib.mkForce false;
}
