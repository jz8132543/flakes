{
  config,
  lib,
  ...
}:
{
  options.ports = lib.mkOption {
    type = with lib.types; attrsOf port;
    default = { };
  };

  config = {
    assertions = [
      {
        assertion =
          let
            vals = lib.attrValues config.ports;
            noCollision = l: lib.length (lib.unique l) == lib.length l;
          in
          noCollision vals;
        message = "ports collision";
      }
    ];

    ports = {
      ssh-honeypot = 22;
      http = 80;
      bgp = 179;
      https = 443;
      https-alternative = 8443;
      ipsec-ike = 500;
      ssh = 1022;
      pastebin = 3000;
      vaultwarden-http = 3010;
      vaultwarden-websocket = 3011;
      influxdb = 3020;
      loki = 3030;
      grafana = 3040;
      alertmanager = 3050;
      hydra = 3070;
      harmonia = 5000;
      matrix = 3090;
      matrix-manhole = 3091;
      mautrix-telegram-appservice = 3100;
      matrix-qq-appservice = 3101;
      minio = 3110;
      minio-console = 3111;
      sigv4-proxy = 3120;
      dot-tar = 3130;
      proxy-http = 3140;
      proxy-socks = 3141;
      proxy-mixed = 3142;
      proxy-tproxy = 3143;
      sing-box-controller = 3150;
      transmission-rpc = 3160;
      elasticsearch = 3170;
      elasticsearch-node-to-node = 3171;
      atticd = 3180;
      oranc = 3190;
      hledger-web = 3200;
      syncthing = 3210;
      syncthing-discovery = 3220;
      syncthing-transfer = 3230;
      gortr = 3240;
      gortr-metric = 3241;
      bird-lg-proxy = 3250;
      bird-lg-frontend = 3251;
      ipsec-nat-traversal = 4500;
      babel = 6696;
      jellyfin = 8096;
      zerotier = 9993;
      dn42-mesh-min = 19000;
      # interval: no ports here
      dn42-mesh-max = 19999;
      dn42-peer-min = 20000;
      # interval: no ports here
      dn42-peer-max = 23999;
      minecraft = 25565;
      minecraft-rcon = 25566;
      minecraft-map = 25567;
      teamspeak-voice = 9987;
      teamspeak-file-transfer = 30033;
      teamspeak-query = 10011;
      syncthing-discovery-yinfeng = 3221;
      syncthing-transfer-yinfeng = 3231;
      plex = 32400;
      vlmcsd = 40044;
      qrcp = 3270;
      tailscale = 41641;
      wireguard = 51820;
      authentik = 9001;
      authentik-ldap = 9000;
      authentik-metrics = 9301;
      authentik-ldap-metrics = 9300;
      nginx = 8080;
      keycloak = 3260;
      lldap = 17170;
      ldap = 389;
      ldaps = 636;
      mta-sts = 8097;
      derp = 3340;
      derp-stun = 3478;
      smtp = 465;
      imap = 993;
      sogo = 20001;
      seafile-file-server = 3060;
      seafile-dav = 3061;
      morty = 3001;
      searx = 8888;
      headscale = 8085;
      headscale_metrics = 8095;
      headscale_grpc = 50443;
      alist = 5244;
      atuin = 3310;
      ntfy = 1161;
      perplexica-frontend = 3002;
      perplexica-backend = 3003;
    };
  };
}
