{
  config,
  ...
}:
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = config.ports.blackbox-exporter;
    listenAddress = "127.0.0.1";
    configFile = ./blackbox.yml;
  };
}
