{ configurations, lib }:
let
  papersMountPoint = "/home/tippy/Storage/Papers";
  arx8 = configurations.arx8.config;
  surface = configurations.surface.config;
  surfaceOffload =
    (configurations.surface.extendModules {
      modules = [ { desktop.nvidia.mode = lib.mkForce "offload"; } ];
    }).config;

  checkHost =
    cfg:
    let
      offload = cfg.desktop.nvidia.mode == "offload";
      checks = {
        vaapiSelection =
          if offload then
            !(cfg.environment.sessionVariables ? LIBVA_DRIVER_NAME)
          else
            cfg.environment.sessionVariables.LIBVA_DRIVER_NAME == "nvidia";
        primeMode =
          cfg.hardware.nvidia.prime.offload.enable == offload
          && cfg.hardware.nvidia.prime.sync.enable == !offload;
        nvidiaVaapiInstalled = lib.any (
          package: lib.getName package == "nvidia-vaapi-driver"
        ) cfg.hardware.graphics.extraPackages;
        standaloneDesktopPreserved =
          cfg.desktop.defaultSession == "umbriel"
          && cfg.programs.umbriel.enable
          && cfg.programs.noctalia.enable
          && !cfg.services.desktopManager.gnome.enable
          && !cfg.services.desktopManager.plasma6.enable
          && !cfg.services.displayManager.sddm.enable
          && !cfg.services.displayManager.gdm.enable
          && cfg.services.displayManager.noctalia-greeter.enable
          && cfg.hardware.nvidia.modesetting.enable
          && cfg.environment.sessionVariables.SDL_VIDEODRIVER == "wayland";
        cleanupExcludesOnlyPapers =
          cfg.systemd.services.systemd-tmpfiles-clean.serviceConfig.ExecStart == [
            ""
            "${cfg.systemd.package}/bin/systemd-tmpfiles --clean --exclude-prefix=${papersMountPoint}"
          ];
        upstreamCleanupPreserved =
          cfg.systemd.services.systemd-tmpfiles-clean.overrideStrategy == "asDropinIfExists"
          && lib.elem "systemd-tmpfiles-clean.service" cfg.systemd.additionalUpstreamSystemUnits
          && !(cfg.systemd.services.systemd-tmpfiles-clean.serviceConfig ? SuccessExitStatus);
        bootCreationPreserved =
          lib.elem "d ${papersMountPoint} 0755 tippy users -" cfg.systemd.tmpfiles.rules
          && lib.elem "systemd-tmpfiles-setup.service" cfg.systemd.additionalUpstreamSystemUnits
          && !(lib.hasInfix "--exclude-prefix=${papersMountPoint}" (
            toString (cfg.systemd.services.systemd-tmpfiles-setup.serviceConfig.ExecStart or "")
          ));
      };
    in
    assert lib.assertMsg (lib.all (value: value) (builtins.attrValues checks)) (builtins.toJSON checks);
    checks;
in
assert lib.assertMsg (
  arx8.desktop.nvidia.mode == "offload"
  && arx8.hardware.nvidia.prime.amdgpuBusId == "PCI:8:0:0"
  && arx8.hardware.nvidia.prime.nvidiaBusId == "PCI:1:0:0"
  && arx8.hardware.nvidia.package.version == arx8.boot.kernelPackages.nvidiaPackages.stable.version
) "arx8 PRIME bus IDs, offload mode and stable NVIDIA selection must be preserved";
assert lib.assertMsg (
  surface.desktop.nvidia.mode == "sync"
  && surface.hardware.nvidia.prime.intelBusId == "PCI:0:2:0"
  && surface.hardware.nvidia.prime.nvidiaBusId == "PCI:2:0:0"
  &&
    surface.hardware.nvidia.package.version
    == surface.boot.kernelPackages.nvidiaPackages.legacy_580.version
  && surfaceOffload.hardware.nvidia.prime.intelBusId == surface.hardware.nvidia.prime.intelBusId
  && surfaceOffload.hardware.nvidia.prime.nvidiaBusId == surface.hardware.nvidia.prime.nvidiaBusId
  && surfaceOffload.hardware.nvidia.package.version == surface.hardware.nvidia.package.version
) "Surface PRIME bus IDs, configured sync mode and legacy NVIDIA pin must be preserved";
{
  arx8 = checkHost arx8;
  surface = checkHost surface;
  surfaceOffload = checkHost surfaceOffload;
}
