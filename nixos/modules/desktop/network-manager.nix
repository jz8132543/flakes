{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    iw
    iwd
  ];

  networking.networkmanager = {
    enable = true;
    # dns = "dnsmasq";
  };
  # services.dnscrypt-proxy.enable = true;
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
  ];
}
