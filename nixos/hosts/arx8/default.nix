{
  nixosModules,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.fakehttp
      nixosModules.optimize.network-desktop
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.optimize.dev
      # nixosModules.services.microsocks
    ];

  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
  ];
  desktop.nvidia = {
    mode = "offload";
  };
  desktop.winapps = {
    kvm = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = false;
    };
    docker = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = false;
      extraDisks = [ "/dev/disk/by-id/nvme-GLOWAY_YCT2TNVMe-M.2_80_T23101205008" ]; # 2TB Game Drive
    };
  };

  # services.create_ap = {
  #   enable = true;
  #   settings = {
  #     INTERNET_IFACE = "wlp4s0";
  #     WIFI_IFACE = "wlp4s0";
  #     SSID = "ARX8";
  #     PASSPHRASE = "qwertyut";
  #     # HIDDEN = 1;
  #     IEEE80211AX = 1;
  #     FREQ_BAND = 5;
  #   };
  # };
  # };

}
