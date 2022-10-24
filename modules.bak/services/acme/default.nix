{ pkgs, config, lib, ... }:

let
  # creds = pkgs.writeTextFile {
  #   name = "cloudflare.env";
  #   text = builtins.readFile ./secret/acme-cf.env;
  # };
  # extraLegoFlags = [ "--dns.resolvers=8.8.8.8:53" ];
  cfg = config.services.acme;

in with lib; {
  sops.secrets.acme-eu = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /acme-eu.keytab;
  };
  sops.secrets.acme-im = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /acme-im.keytab;
  };

  options.services.acme = {
    enable = _.mkBoolOpt false;
  };

  security = mkIf cfg.enable{
    acme.defaults.email = "blackhole@dora.im";
    acme.acceptTerms = true;
    acme.certs."tippic.eu.org" = {
      group = "nginx";
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.secrets.acme-eu.path;
      extraDomainNames = [ "*.tippic.eu.org" ];
      # inherit extralegoflags;
    };
    acme.certs."dora.im" = {
      group = "nginx";
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.secrets.acme-im.path;
      extraDomainNames =
        [ "*.dora.im" "*.${config.networking.hostName}.dora.im" ];
      # inherit extralegoflags;
    };
  };
}

