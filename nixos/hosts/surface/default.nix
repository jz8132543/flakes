{
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  surfaceDisplayAutoPy = ./surface-display-auto.py;
  nvidiaPciDevice = "0000:02:00.0";

  surfaceDisplayAuto = pkgs.writeShellApplication {
    name = "surface-display-auto";
    runtimeInputs = [
      pkgs.python3
      pkgs.glib
      pkgs.systemd
    ];
    text = ''
      exec ${pkgs.python3.interpreter} ${surfaceDisplayAutoPy} "$@"
    '';
  };

  surfaceDisplayDiagnose = pkgs.writeShellApplication {
    name = "surface-display-diagnose";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.gnugrep
      pkgs.pciutils
      pkgs.ripgrep
      pkgs.systemd
      pkgs.usbutils
      surfaceDisplayAuto
    ];
    text = builtins.readFile ./surface-display-diagnose.sh;
  };

  surfaceDisplayRecover = pkgs.writeShellApplication {
    name = "surface-display-recover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.glib
      pkgs.systemd
      surfaceDisplayAuto
      surfaceDisplayDiagnose
    ];
    text = builtins.readFile ./surface-display-recover.sh;
  };

  gpuAutoOffload = pkgs.writeShellApplication {
    name = "gpu-auto-offload";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu

      if [ "$#" -eq 0 ]; then
        echo "usage: gpu-auto-offload <program> [args...]" >&2
        exit 64
      fi

      nvidia_device="/sys/bus/pci/devices/${nvidiaPciDevice}"

      if [ -r "$nvidia_device/vendor" ] && [ "$(cat "$nvidia_device/vendor")" = "0x10de" ] && [ -c /dev/nvidiactl ]; then
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
      fi

      exec "$@"
    '';
  };

  gpuWrappedApps = pkgs.symlinkJoin {
    name = "surface-gpu-wrapped-apps";
    paths =
      map
        (
          {
            name,
            command,
          }:
          pkgs.writeShellApplication {
            inherit name;
            text = ''
              exec ${gpuAutoOffload}/bin/gpu-auto-offload ${command} "$@"
            '';
          }
        )
        [
          {
            name = "google-chrome-stable";
            command = "${pkgs.google-chrome}/bin/google-chrome-stable";
          }
          {
            name = "chromium";
            command = "${pkgs.chromium}/bin/chromium";
          }
          {
            name = "firefox";
            command = "${pkgs.firefox}/bin/firefox";
          }
          {
            name = "code";
            command = "${pkgs.vscode}/bin/code";
          }
          {
            name = "cursor";
            command = "${pkgs.code-cursor}/bin/cursor";
          }
          {
            name = "antigravity";
            command = "${pkgs.google-antigravity}/bin/antigravity";
          }
        ];
  };
in
{
  disabledModules = [
    ../../modules/desktop/nvidia.nix
  ];

  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.media.qbittorrent
    ];

  hardware.microsoft-surface = {
    kernelVersion = "stable";
  };
  services.iptsd.enable = lib.mkDefault true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    SDL_VIDEODRIVER = "wayland";
  };

  home-manager.users.tippy = {
    home.sessionPath = [
      "${gpuWrappedApps}/bin"
    ];
  };

  users.users.tippy.extraGroups = [ "surface-control" ];

  # services.create_ap = {
  #   enable = true;
  #   settings = {
  #     INTERNET_IFACE = "wlp1s0";
  #     WIFI_IFACE = "wlp1s0";
  #     SSID = "ARX8";
  #     PASSPHRASE = "qwertyut";
  #     # HIDDEN = 1;
  #     IEEE80211AX = 1;
  #     FREQ_BAND = 5;
  #   };
  # };

  # environment.isCN = true;

  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    surface-control
    surfaceDisplayAuto
    surfaceDisplayDiagnose
    surfaceDisplayRecover
    gpuAutoOffload
    gpuWrappedApps
    usbutils
    v4l-utils
  ];

  systemd.user.services.surface-display-auto = {
    description = "Automatically switch Surface to external-only when an external monitor appears";
    wantedBy = [
      "default.target"
      "graphical-session.target"
    ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${surfaceDisplayAuto}/bin/surface-display-auto watch";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
