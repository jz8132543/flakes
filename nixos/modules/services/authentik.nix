{ config, inputs, ... }:

{
  imports = [
    inputs.authentik-nix.nixosModules.default
  ];
  services = {
    authentik = {
      enable = true;
      createDatabase = false;
      nginx.enable = false;
      environmentFile = config.sops.templates.authentik-env.path;

      settings = {
        email = {
          host = config.environment.smtp_host;
          port = config.environment.smtp_port;
          use_ssl = true;
          from = "authentik@dora.im";
          username = "authentik@dora.im";
          # username and password are in the secrets
        };

        postgresql = {
          host = "localhost";
          name = "authentik";
          user = "authentik";
          port = 5432;
        };

        redis = {
          db = 1;
        };

        error_reporting = {
          enabled = false;
        };
        disable_startup_analytics = true;
        disable_update_check = true;
      };
    };
  };
  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik/SECRET_KEY"}
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."authentik/EMAIL_PASSWORD"}
    '';
  };
  sops.secrets = {
    "authentik/EMAIL_PASSWORD" = { };
    "authentik/SECRET_KEY" = { };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      authentik = {
        # rule = "Host(`sso.${config.networking.domain}`) && PathPrefix(`/outpost.goauthentik.io/`)";
        rule = "Host(`sso.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "authentik";
      };
    };
    services = {
      authentik.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:9000"; } ];
      };
    };
    middlewares = {
      authentik = {
        forwardAuth = {
          tls.insecureSkipVerify = true;
          address = "https://localhost:9443/outpost.goauthentik.io/auth/traefik";
          trustForwardHeader = true;
          authResponseHeaders = [
            "X-authentik-username"
            "X-authentik-groups"
            "X-authentik-email"
            "X-authentik-name"
            "X-authentik-uid"
            "X-authentik-jwt"
            "X-authentik-meta-jwks"
            "X-authentik-meta-outpost"
            "X-authentik-meta-provider"
            "X-authentik-meta-app"
            "X-authentik-meta-version"
          ];
        };
      };
    };
  };
}
