{
  nixosModules,
  lib,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      ./_steam
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.services.postgres
      nixosModules.services.derp
      (import nixosModules.services.matrix {PG = "127.0.0.1";})
    ];
  # environment.isNAT = true;
  environment.isCN = true;

  ports.derp-stun = lib.mkForce 3440;
  services.traefik.staticConfigOptions.entryPoints.https.address = lib.mkForce ":8443";
  networking.firewall = {
    # enable = lib.mkForce false;
    # extraCommands = ''
    #   iptables -t nat -A PREROUTING -p tcp --dport 8443 -j REDIRECT --to-port 443
    #   iptables -t nat -A PREROUTING -p udp --dport 8443 -j REDIRECT --to-port 443
    #   iptables -t nat -A OUTPUT -p tcp --dport 8443 -j REDIRECT --to-port 443
    #   iptables -t nat -A OUTPUT -p udp --dport 8443 -j REDIRECT --to-port 443
    # '';
    allowedUDPPortRanges = [
      {
        from = 0;
        to = 65535;
      }
    ];
    allowedTCPPortRanges = [
      {
        from = 0;
        to = 65535;
      }
    ];
    allowedTCPPorts = [8443];
    allowedUDPPorts = [8443];
  };
}
