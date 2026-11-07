{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  surfaceModule = inputs.nixos-hardware.nixosModules.microsoft-surface-common;
  surfaceKernel =
    (import surfaceModule { inherit config lib pkgs; }).config.boot.kernelPackages.kernel;
  latestKernel = pkgs.linuxPackages_latest.kernel;
  kernelSeries = lib.versions.majorMinor latestKernel.version;
  patchDir = "${inputs.linux-surface}/patches/${kernelSeries}";
  configFile = "${inputs.linux-surface}/configs/surface-${kernelSeries}.config";
in
{
  imports = [ surfaceModule ];

  # ==========================================
  # Surface 核心硬件与内核配置
  # ==========================================
  # Keep the nixos-hardware Surface kernel builder, but track nixpkgs sources.
  # Update both inputs with: nix flake update nixpkgs linux-surface
  boot.kernelPackages = lib.mkForce (
    assert lib.assertMsg (builtins.pathExists patchDir && builtins.pathExists configFile)
      "linux-surface has no patches/config for Linux ${kernelSeries}; update the linux-surface input before upgrading the kernel.";
    pkgs.linuxPackagesFor (
      surfaceKernel.override {
        inherit (latestKernel) src version modDirVersion;
        ignoreConfigErrors = false;
        kernelPatches = map (name: {
          name = "ms-surface/${name}";
          patch = "${patchDir}/${name}";
        }) (lib.filter (lib.hasSuffix ".patch") (builtins.attrNames (builtins.readDir patchDir)));
        # Translate the matching upstream Kconfig fragment to Nix's name/value format.
        # Disabled symbols may no longer exist; enabled drivers remain required.
        extraConfig =
          lib.concatMapStringsSep "\n"
            (lib.replaceStrings [ "# CONFIG_" "CONFIG_" "=" " is not set" ] [ "" "" " " "? n" ])
            (
              lib.filter (line: lib.hasPrefix "CONFIG_" line || lib.hasPrefix "# CONFIG_" line) (
                lib.splitString "\n" (builtins.readFile configFile)
              )
            );
      }
    )
  );

  # nix.settings.substituters = ["https://linux-surface.cachix.org"];
  # nix.settings.trusted-public-keys = [
  #   "linux-surface.cachix.org-1:QfXYqHXil6OIWq9lro4kQEnOS0qV8OmtJ2e0YcW8nKE="
  # ];

  # ==========================================
  # GPU 与显示配置
  # ==========================================
  desktop.nvidia = {
    mode = "sync";
  };

  # ==========================================
  # 触屏、电源管理与驱动优化
  # ==========================================
  # 开启触屏支持
  # services.iptsd.enable = true;

  # 电源管理：禁用可能导致休眠死机的 TLP，改用 power-profiles-daemon
  # services.power-profiles-daemon.enable = true;
  # services.tlp.enable = false;

  # 修复由于不受支持的 IPU6 摄像头导致的 Wireplumber 异常
  # services.pipewire.wireplumber.extraConfig = {
  #   "50-surface-disable-libcamera" = {
  #     "monitor.libcamera" = "disabled";
  #     "wireplumber.profiles" = {
  #       main = {
  #         "monitor.libcamera" = "disabled";
  #         "hardware.video-capture" = "disabled";
  #       };
  #     };
  #   };
  # };

  # ==========================================
  # Surface 特殊功能权限 (DTX/控制组)
  # ==========================================
  # users.groups.surface-control = {};
  # users.users.tippy.extraGroups = ["surface-control"];

  # ==========================================
  # 硬件控制与系统工具包
  # ==========================================
  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    usbutils
    v4l-utils

    # Surface 相关工具
    # surface-control
  ];
}
