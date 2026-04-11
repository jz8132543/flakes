{
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  surfaceDisplayAutoPy = ./surface-display-auto.py;

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
in
{
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
      nixosModules.services.qbittorrent
    ];

  hardware.microsoft-surface = {
    kernelVersion = "stable";
  };
  services.iptsd.enable = lib.mkDefault true;

  desktop.nvidia = {
    mode = "sync";
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
