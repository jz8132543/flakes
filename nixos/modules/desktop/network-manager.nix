{pkgs, ...}: {
  environment.persistence."/nix/persist".directories = [
    "/etc/NetworkManager/system-connections"
  ];

  environment.systemPackages = with pkgs; [iw iwd];

  users.users.tippy.extraGroups = ["networkmanager"];

  networking.networkmanager = {
    enable = true;
    enableFccUnlock = true;
    # dns = "dnsmasq";
    firewallBackend = "none";
    connectionConfig = {
      "ipv4.dns-search" = "dora.im";
      "ipv6.dns-search" = "dora.im";
    };
  };
}
