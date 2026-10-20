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

  winappsPatched = winappsBase.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace bin/winapps \
        --replace-fail 'podman-compose --file "$COMPOSE_PATH" pause' 'podman pause "$CONTAINER_NAME"' \
        --replace-fail '$COMPOSE_COMMAND --file "$COMPOSE_PATH" unpause' 'if [ "$WAFLAVOR" = "podman" ]; then podman unpause "$CONTAINER_NAME"; else $COMPOSE_COMMAND --file "$COMPOSE_PATH" unpause; fi' \
        --replace-fail '$COMPOSE_COMMAND --file "$COMPOSE_PATH" start' 'if [ "$WAFLAVOR" = "podman" ]; then podman start "$CONTAINER_NAME"; else $COMPOSE_COMMAND --file "$COMPOSE_PATH" start; fi'
    '';
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
        # WinApps package from the community flake (patched for native podman pause/unpause)
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
