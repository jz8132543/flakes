{ ... }:
{
  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        FallbackDNS = [ ];
        Domains = [ ];
        DNSSEC = false;
        MulticastDNS = false;
        LLMNR = false;
        Cache = true;
        DNSStubListener = true;
      };
    };
  };
  networking.resolvconf.enable = false;

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
