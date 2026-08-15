{
  nixosModules,
  lib,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      ./hardware.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.qbittorrent
    ];

  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  # hardware.microsoft-surface = {
  #   kernelVersion = "longterm";
  # };
  services.iptsd.enable = lib.mkForce false;

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

  # environment.networkTune.cca = "bbr";
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
