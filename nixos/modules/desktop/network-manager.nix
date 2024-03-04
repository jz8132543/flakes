{pkgs, ...}: {
  environment.systemPackages = with pkgs; [iw iwd];

  networking.networkmanager = {
    enable = true;
    # dns = "dnsmasq";
  };
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
  ];
}
