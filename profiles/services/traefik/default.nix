{ pkgs, lib, config, ... }:

{
  imports = [ ./services.nix ];
  sops.secrets.traefik = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /traefik.keytab;
  };
  # sops.secrets."traefik/KID" = {
  #   sopsFile = ../../secrets/traefik.yaml;
  # };
  # sops.secrets."traefik/HMAC" = {
  #   sopsFile = ../../secrets/traefik.yaml;
  # };
  services.traefik = {
    enable = true;
    staticConfigOptions = {
      experimental.http3 = true;
      entryPoints = {
        http = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "https";
            scheme = "https";
            permanent = false;
          };
        };
        https = {
          address = ":443";
          http.tls.certResolver = "le";
          http3 = { };
        };
      };
      certificatesResolvers.le.acme = {
        # caServer = "https://acme.zerossl.com/v2/DV90";
        email = "blackhole@dora.im";
        storage = config.services.traefik.dataDir + "/acme.json";
        keyType = "EC256";
        dnsChallenge = { provider = "cloudflare"; };
        # eab = {
        #   kid = config.sops.secrets.placeholder."traefik/KID";
        #   hmacEncoded = config.sops.secrets.placeholder."traefik/KIDHMAC";
        # };
      };
      ping = { manualRouting = true; };
      api = { dashboard = true; };
      accessLog = { filePath = "/tmp/access.log"; };
      log = {
        filePath = "/tmp/traefik.log";
        level = "DEBUG";
      };
      providers = { kubernetesIngress = { }; };
    };
    dynamicConfigOptions = {
      tls.options.default = {
        minVersion = "VersionTLS13";
        sniStrict = true;
      };
    };
  };
  # systemd.services.traefik.serviceConfig.EnvironmentFile = config.sops.secrets.traefik.path;
  # Added k3s systemd configure
}
