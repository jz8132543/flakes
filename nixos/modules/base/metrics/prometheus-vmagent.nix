{
  config,
  pkgs,
  ...
}:
let
  remoteWriteUrl = "https://metrics.${config.networking.domain}/api/v1/write";
  scrapeConfig = pkgs.writeText "vmagent-promscrape.yml" ''
    scrape_configs:
      - job_name: hosts
        static_configs:
          - targets:
              - 127.0.0.1:${toString config.services.prometheus.exporters.node.port}
            labels:
              instance: ${config.networking.hostName}
      - job_name: hosts
        static_configs:
          - targets:
              - 127.0.0.1:${toString config.services.prometheus.exporters.nix-registry.port}
            labels:
              instance: ${config.networking.hostName}
  '';
in
{
  systemd.services.prometheus-vmagent = {
    description = "Push node metrics to metrics.dora.im";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.vmagent}/bin/vmagent -promscrape.config=${scrapeConfig} -remoteWrite.url=${remoteWriteUrl} -remoteWrite.tmpDataPath=%C/prometheus-vmagent/remote_write_tmp";
      Restart = "always";
      RestartSec = "10s";
      DynamicUser = true;
      StateDirectory = "prometheus-vmagent";
    };
  };
}
