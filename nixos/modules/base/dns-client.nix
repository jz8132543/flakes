{
  lib,
  config,
  ...
}:
let
  cfg = config.services.dnscrypt-proxy2;
in
{
  networking =
    if cfg.enable then
      {
        # nameservers = ["127.0.0.2" "127.0.0.55"];
        nameservers = [ "127.0.0.55" ];
        # resolvconf.enable = lib.mkForce false;
        dhcpcd.extraConfig = "nohook resolv.conf";
        networkmanager.dns = lib.mkForce "none";
        # resolvconf.useLocalResolver = true;
      }
    else
      { };
  services = {
    resolved =
      if cfg.enable then
        {
          enable = true;
          dnssec = "allow-downgrade";
          extraConfig = ''
            MulticastDNS=true
            DNSStubListener=no
          '';
          fallbackDns = if config.services.tailscale.enable then [ "100.100.100.100" ] else [ ];
        }
      else
        { };
    dnscrypt-proxy2 = rec {
      enable = lib.mkDefault false;
      settings = {
        listen_addresses = [ "127.0.0.55:53" ];
        ipv4_servers = true;
        ipv6_servers = true;
        dnscrypt_servers = true;
        require_dnssec = true;
        doh_servers = true;
        odoh_servers = true;
        require_nolog = true;
        ignore_system_dns = true;
        bootstrap_resolvers = [
          "1.1.1.1:53"
          "1.0.0.1:53"
          "9.9.9.9:53"
          "119.29.29.29:53"
          "223.5.5.5:53"
        ];
        # fallback_resolvers = ["1.1.1.1:53" "1.0.0.1:53" "119.29.29.29:53" "223.5.5.5:53"];
        cache = true;

        sources = { };
        # sources = {
        #   public-resolvers.urls = [];
        #   relays.urls = [];
        # };

        # sources.public-resolvers = {
        #   urls = [
        #     "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
        #     "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
        #   ];
        #   cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
        #   minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
        # };
        static = {
          quad9-doh-ip4-port5053-filter-pri.stamp = "sdns://AgMAAAAAAAAABzkuOS45LjkgKhX11qy258CQGt5Ou8dDsszUiQMrRuFkLwaTaDABJYoTZG5zOS5xdWFkOS5uZXQ6NTA1MwovZG5zLXF1ZXJ5";
          quad9-doh-ip4-port443-filter-pri.stamp = "sdns://AgMAAAAAAAAABzkuOS45LjkgKhX11qy258CQGt5Ou8dDsszUiQMrRuFkLwaTaDABJYoSZG5zOS5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk";
          quad9-doh-ip6-port5053-filter-pri.stamp = "sdns://AgMAAAAAAAAADVsyNjIwOmZlOjpmZV0gKhX11qy258CQGt5Ou8dDsszUiQMrRuFkLwaTaDABJYoSZG5zLnF1YWQ5Lm5ldDo1MDUzCi9kbnMtcXVlcnk";
          quad9-doh-ip6-port443-filter-pri.stamp = "sdns://AgMAAAAAAAAADVsyNjIwOmZlOjpmZV0gKhX11qy258CQGt5Ou8dDsszUiQMrRuFkLwaTaDABJYoRZG5zLnF1YWQ5Lm5ldDo0NDMKL2Rucy1xdWVyeQ";
          iij.stamp = "sdns://AgcAAAAAAAAACjEwMy4yLjU3LjYAEXB1YmxpYy5kbnMuaWlqLmpwCi9kbnMtcXVlcnk";
          cloudflare.stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
        };

        # You can choose a specific set of servers from https://github.com/DNSCrypt/dnscrypt-resolvers/blob/master/v3/public-resolvers.md
        server_names = [
          # "cloudflare"
          # "google"
          "quad9-doh-ip4-port5053-filter-pri"
          "quad9-doh-ip4-port443-filter-pri"
          "quad9-doh-ip6-port5053-filter-pri"
          "quad9-doh-ip6-port443-filter-pri"
          "iij"
          # "cloudflare-security-ipv6"
          # "doh-crypto-sx"
          # "alidns-doh"
        ];
      };
    };
  };
  # Add polkit rule to allow systemd-resolved to change DNS config
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (subject.isInGroup("systemd-resolve") && (
            action.id == "org.freedesktop.resolve1.register-service" ||
            action.id == "org.freedesktop.resolve1.revert" ||
            action.id == "org.freedesktop.resolve1.set-default-route" ||
            action.id == "org.freedesktop.resolve1.set-dns-over-tls" ||
            action.id == "org.freedesktop.resolve1.set-dns-servers" ||
            action.id == "org.freedesktop.resolve1.set-dnssec" ||
            action.id == "org.freedesktop.resolve1.set-dnssec-negative-trust-anchors" ||
            action.id == "org.freedesktop.resolve1.set-domains" ||
            action.id == "org.freedesktop.resolve1.set-llmnr" ||
            action.id == "org.freedesktop.resolve1.set-mdns" ||
            action.id == "org.freedesktop.resolve1.unregister-service"
        )) {
            return polkit.Result.YES;
        }
    });
  '';
}
