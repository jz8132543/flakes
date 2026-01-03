{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    iw
    iwd
  ];

  networking.networkmanager = {
    enable = true;
    insertNameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    # dns = "dnsmasq";
  };
  # services.dnscrypt-proxy.enable = true;
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
  ];
}
