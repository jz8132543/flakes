{
  config,
  ...
}:
let
  telegrafConfig = config.services.telegraf.extraConfig;
in
{
  services.telegraf = {
    enable = true;
    extraConfig = {
      inputs = {
        cpu = { };
        disk = {
          ignore_fs = [
            "tmpfs"
            "devtmpfs"
            "devfs"
            "overlay"
            "aufs"
            "squashfs"
          ];
        };
        diskio = { };
        mem = { };
        net = { };
        processes = { };
        system = { };
        systemd_units = { };
        dns_query = {
          servers = [
            "1.1.1.1"
            "1.0.0.1"
          ];
          domains = [ "dora.im" ];
          record_type = "A";
          timeout = 5;
        };
      };
      outputs = {
        prometheus_client = {
          listen = "127.0.0.1:9273";
          metric_version = 2;
          path = "/metrics";
        };
      };
    };
  };
  services.traefik = {
    dynamicConfigOptions = {
      http = {
        routers.telegraf = {
          rule = "Host(`${config.networking.fqdn}`) && Path(`${telegrafConfig.outputs.prometheus_client.path}`)";
          entryPoints = [ "https" ];
          service = "telegraf";
        };
        services.telegraf.loadBalancer.servers = [
          { url = "http://${telegrafConfig.outputs.prometheus_client.listen}"; }
        ];
      };
    };
  };
}
