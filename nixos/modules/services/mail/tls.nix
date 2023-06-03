{config, ...}: {
  networking.firewall.allowedTCPPorts = [25 465 993];
  services.traefik = {
    staticConfigOptions = {
      entryPoints = {
        imap.address = ":993";
        submission.address = ":465";
      };
    };
    dynamicConfigOptions = {
      tcp = {
        routers = {
          imap = {
            rule = "HostSNI(`${config.networking.fqdn}`)";
            entryPoints = ["imap"];
            service = "imap";
            tls.certResolver = "zerossl";
          };
          submission = {
            rule = "HostSNI(`${config.networking.fqdn}`)";
            entryPoints = ["submission"];
            service = "submission";
            tls.certResolver = "zerossl";
          };
        };
        services = {
          imap.loadBalancer = {
            proxyProtocol = {};
            servers = [{address = "127.0.0.1:8143";}];
          };
          submission.loadBalancer = {
            proxyProtocol = {};
            servers = [{address = "127.0.0.1:587";}];
          };
        };
      };
    };
  };
}
