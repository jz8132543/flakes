{pkgs, ...}: {
  environment.systemPackages = with pkgs; [iw iwd];

  users.users.tippy.extraGroups = ["networkmanager"];

  networking.networkmanager = {
    enable = true;
    # dns = "dnsmasq";
    firewallBackend = "nftables";
    connectionConfig = {
      "ipv4.dns-search" = "dora.im";
      "ipv6.dns-search" = "dora.im";
    };
  };
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
  ];
}
