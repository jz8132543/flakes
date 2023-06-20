{config, ...}: {
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "blackhole@dora.im";
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.templates.acme-credentials.path;
      # server = "https://acme.zerossl.com/v2/DV90";
      # extraLegoFlags = config.sops.templates.acme-flag.path;
    };
  };
  security.acme.certs."main" = {
    domain = "*.dora.im";
    extraDomainNames = [
      "*.ts.dora.im"
    ];
  };
  sops.secrets = {
    "traefik/cloudflare_token" = {};
    # "traefik/KID" = {};
    # "traefik/HMAC" = {};
  };
  sops.templates.acme-credentials = {
    owner = "acme";
    content = ''
      CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."traefik/cloudflare_token"}
    '';
  };
  # sops.templates.acme-flag.content = ''
  #   --eab
  #   --kid=${config.sops.placeholder."traefik/KID"}
  #   --hmac=${config.sops.placeholder."traefik/HMAC"}
  # '';
}
