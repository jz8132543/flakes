{ pkgs, config, lib, ... }:

let
  # creds = pkgs.writeTextFile {
  #   name = "cloudflare.env";
  #   text = builtins.readFile ./secret/acme-cf.env;
  # };
  # extraLegoFlags = [ "--dns.resolvers=8.8.8.8:53" ];

in {
  sops.secrets.acme-eu = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /acme-eu.keytab;
  };
  sops.secrets.acme-im = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /acme-im.keytab;
  };

  security.acme.defaults.email = "blackhole@dora.im";
  security.acme.acceptTerms = true;

  security.acme.certs."tippic.eu.org" = {
    group = "nginx";
    dnsProvider = "cloudflare";
    credentialsFile = config.sops.secrets.acme-eu.path;
    extraDomainNames = [ "*.tippic.eu.org" ];
    # inherit extralegoflags;
  };
  security.acme.certs."tippy.ml" = {
    group = "nginx";
    dnsProvider = "cloudflare";
    credentialsFile = config.sops.secrets.acme-eu.path;
    extraDomainNames = [ "*.tippy.ml" ];
    # inherit extralegoflags;
  };
  security.acme.certs."dora.im" = {
    group = "nginx";
    dnsProvider = "cloudflare";
    credentialsFile = config.sops.secrets.acme-im.path;
    extraDomainNames =
      [ "*.dora.im" "*.${config.networking.hostName}.dora.im" ];
    # inherit extralegoflags;
  };
}

