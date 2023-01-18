{ config, lib, ... }:

lib.mkMerge [
  {
    # services.resolved = {
    #   enable = true;
    #   dnssec = "allow-downgrade";
    #   fallbackDns = [
    #     # Cloudflare public DNS
    #     "1.1.1.1"
    #     "1.0.0.1"
    #     "2606:4700:4700::1111"
    #     "2606:4700:4700::1001"
    #     # Google public DNS
    #     "8.8.8.8"
    #     "8.8.4.4"
    #     "2001:4860:4860::8888"
    #     "2001:4860:4860::8844"
    #   ];
    # };
    # networking.firewall.allowedUDPPorts = [ 5353 ];
    networking.nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  }
  (lib.mkIf config.services.avahi.enable {
    services.resolved.extraConfig = ''
      MulticastDNS=resolve
    '';
  })
]
