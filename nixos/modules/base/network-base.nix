{
  config,
  lib,
  ...
}:
{
  services.resolved.enable = false;

  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    resolveLocalQueries = false;
    settings = {
      bind-interfaces = true;
      listen-address = "127.0.0.1";
      cache-size = 10000;
      no-negcache = true;
      no-poll = true;
      no-resolv = true;
      server = [
        "1.1.1.1"
        "1.0.0.1"
        "223.5.5.5"
      ]
      ++ lib.optional config.services.tailscale.enable "/mag/100.100.100.100"
      ++ lib.optional config.services.easytierMesh.enable "/et/${config.services.easytierMesh.dnsServer}";
    };
  };

  networking = {
    nameservers = [ "127.0.0.1" ];
    resolvconf.enable = false;
  };

  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
    options edns0
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
}
