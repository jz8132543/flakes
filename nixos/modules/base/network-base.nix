{ lib, ... }:
{
  services.resolved.enable = false;
  networking.resolvconf.enable = false;
  networking.networkmanager.dns = "none";
  services.dnsmasq.resolveLocalQueries = false;
  # Keep a dedicated loopback address for the local resolver so we do not
  # collide with other services that may also want to bind 127.0.0.1:53.
  networking.nameservers = [ "127.0.0.55" ];
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.55
  '';

  # Prefer IPv4 when both address families are available.
  environment.etc."gai.conf".text = ''
    label  ::1/128       0
    label  ::ffff:0:0/96 1
    label  ::/0          2
    label  2002::/16     3
    label  ::/96         4
    precedence  ::1/128       50
    precedence  ::ffff:0:0/96  100
    precedence  ::/0          40
    precedence  2002::/16     30
    precedence  ::/96         20
  '';

  services.dnsmasq = {
    enable = true;
    settings = {
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      bind-interfaces = true;
      listen-address = [ "127.0.0.55" ];
      server = lib.mkBefore [
        "1.1.1.1"
        "1.0.0.1"
      ];
    };
  };
}
