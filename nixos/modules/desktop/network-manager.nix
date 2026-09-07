{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    iw
    iwd
  ];

  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;
    dns = "none";
  };
  # services.dnscrypt-proxy.enable = true;
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/NetworkManager"
  ];
}
