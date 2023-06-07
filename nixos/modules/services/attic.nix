{
  inputs,
  config,
  ...
}: let
  data = config.lib.self.data;
in {
  imports = [
    inputs.attic.nixosModules.atticd
  ];
  services.atticd = {
    enable = true;
    credentialsFile = config.sops.templates."atticd-credentials".path;
    settings = {
      listen = "[::]:${toString config.ports.atticd}";
      api-endpoint = "https://attic.dora.im/";

      database.url = "postgresql://attic@postgres.dora.im/attic";
      storage = {
        type = "s3";
        region = data.attic.region;
        bucket = data.attic.name;
        endpoint = data.attic.host;
      };
      chunking = {
        # disable chunking
        nar-size-threshold = 0;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
      compression = {
        type = "zstd";
      };
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "2 weeks";
      };
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      attic = {
        rule = "Host(`attic.dora.im`)";
        entryPoints = ["https"];
        service = "attic";
      };
    };
    services = {
      attic.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.atticd}";}];
      };
    };
  };
  sops.secrets = {
    "b2/keyID" = {};
    "b2/applicationKey" = {};
    "atticd" = {};
  };
  sops.templates."atticd-credentials".content = ''
    ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=${config.sops.placeholder."atticd"}
    AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2/keyID"}
    AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2/applicationKey"}
  '';
}
