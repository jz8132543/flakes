{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:

let
  cfg = config.desktop.winapps;
  system = pkgs.stdenv.hostPlatform.system;
  winappsBase = inputs.winapps.packages.${system}.winapps;

  # 仅做增值封装，不修改 WinApps 官方脚本逻辑：
  # 1. 将 WinApps 自带的 Office/Windows SVG 图标安装进 hicolor 主题
  # 2. 把 podman-compose 与 slirp4netns 加入 wrapper 的 PATH（官方 AUTOPAUSE 的 pause/unpause 及网络隔离依赖它们）
  winappsPatched = winappsBase.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [
      pkgs.podman-compose
      pkgs.slirp4netns
    ];
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/share/icons/hicolor/scalable/apps
      for app in word excel powerpoint explorer; do
        if [ -f "$out/src/apps/$app/icon.svg" ]; then
          case "$app" in
            word) cp "$out/src/apps/$app/icon.svg" $out/share/icons/hicolor/scalable/apps/ms-word.svg ;;
            excel) cp "$out/src/apps/$app/icon.svg" $out/share/icons/hicolor/scalable/apps/ms-excel.svg ;;
            powerpoint) cp "$out/src/apps/$app/icon.svg" $out/share/icons/hicolor/scalable/apps/ms-powerpoint.svg ;;
            explorer) cp "$out/src/apps/$app/icon.svg" $out/share/icons/hicolor/scalable/apps/distributor-logo-windows.svg ;;
          esac
        fi
      done
    '';
  });
in
{
  config = lib.mkIf (cfg.kvm.enable || cfg.docker.enable || cfg.podman.enable) {
    environment.systemPackages =
      with pkgs;
      [
        # Virtual Machine Manager GUI
        virt-manager
        # FreeRDP is required by WinApps to connect to the VM seamlessly
        freerdp
        # WinApps uses podman-compose to manage the container lifecycle (incl. AUTOPAUSE)
        podman-compose
        # User-mode networking for rootless Podman (resilient against complex host route tables like DN42/BGP)
        slirp4netns
        # WinApps package from the community flake
        winappsPatched
        inputs.winapps.packages.${system}.winapps-launcher
      ]
      ++ lib.optionals cfg.kvm.enable [
        # Dependencies for KVM dynamic disk discovery script
        os-prober
        util-linux
      ];
  };
}
