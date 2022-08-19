{ config, ... }:

{
  services.traefik = {
    staticConfigOptions = {
      entryPoints = {
        imap = {
          address = ":993";
          http.tls.certResolver = "le";
        };
        submission = {
          address = ":465";
          http.tls.certResolver = "le";
        };
      };
    };
    dynamicConfigOptions = {
      # tcp = {
      #   routers = {
      #     imap = {
      #       rule = "HostSNI(`${config.networking.fqdn}`)";
      #       entryPoints = [ "imap" ];
      #       service = "imap";
      #       tls = { };
      #     };
      #     submission = {
      #       rule = "HostSNI(`${config.networking.fqdn}`)";
      #       entryPoints = [ "submission" ];
      #       service = "submission";
      #       tls = { };
      #     };
      #   };
      #   services = {
      #     imap.loadBalancer.servers = [{ address = "127.0.0.1:143"; }];
      #     submission.loadBalancer.servers = [{ address = "127.0.0.1:587"; }];
      #   };
      # };
      http = {
        routers = {
          ping = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/`)";
            entryPoints = [ "https" ];
            service = "ping@internal";
          };
          dashboard = {
            rule = "Host(`${config.networking.fqdn}`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))";
            entryPoints = [ "https" ];
            service = "api@internal";
            middlewares = "auth";
          };
        };
        middlewares = {
          compress.compress = { };
          auth.basicauth.users = "tippy:$2y$10$oTDoQ9/2nwg8CpPQkeKT../Bkll8XQSwzx4zjJSNimQ/PJCT4i.3C";
        };
        # services = {
        #   k3s.loadBalancer = {
        #     passHostHeader = true;
        #     servers = [{ url = "https://127.0.0.1:6444"; }];
        #     # servers = [{ url = "http://${config.services.searxng.settings.server.port}"; }];
        #   };
        # };
      };
    };
  };
}
