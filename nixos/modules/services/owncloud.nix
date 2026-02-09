{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.keycloak ];
  services.ocis = {
    enable = true;
    url = "https://cloud.${config.networking.domain}";
    environment =
      let
        cspFormat = pkgs.formats.yaml { };
        cspConfig = {
          directives = {
            child-src = [ "'self'" ];
            connect-src = [
              "'self'"
              "blob:"
              "https://${config.services.keycloak.settings.hostname}"
            ];
            default-src = [ "'none'" ];
            font-src = [ "'self'" ];
            frame-ancestors = [ "'none'" ];
            frame-src = [
              "'self'"
              "blob:"
              "https://embed.diagrams.net"
            ];
            img-src = [
              "'self'"
              "data:"
              "blob:"
            ];
            manifest-src = [ "'self'" ];
            media-src = [ "'self'" ];
            object-src = [
              "'self'"
              "blob:"
            ];
            script-src = [
              "'self'"
              "'unsafe-inline'"
            ];
            style-src = [
              "'self'"
              "'unsafe-inline'"
            ];
          };
        };
      in
      {
        PROXY_AUTOPROVISION_ACCOUNTS = "true";
        PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
        OCIS_OIDC_ISSUER = "https://${config.services.keycloak.settings.hostname}/realms/master";
        PROXY_OIDC_REWRITE_WELLKNOWN = "true";
        WEB_OIDC_CLIENT_ID = "ocis";
        OCIS_LOG_LEVEL = "error";
        PROXY_TLS = "false";
        PROXY_USER_OIDC_CLAIM = "preferred_username";
        PROXY_USER_CS3_CLAIM = "username";
        OCIS_ADMIN_USER_ID = "i";
        OCIS_INSECURE = "false";
        OCIS_EXCLUDE_RUN_SERVICES = "idp";
        GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
        PROXY_CSP_CONFIG_FILE_LOCATION = toString (cspFormat.generate "csp.yaml" cspConfig);
        GRAPH_USERNAME_MATCH = "none";
        PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
      };
  };
  # systemd.services.nextcloud-config-collabora =
  #   let
  #     inherit (config.services.nextcloud) occ;
  #
  #     wopi_url = "http://[::1]:${toString config.ports.office}";
  #     public_wopi_url = "https://${config.services.collabora-online.settings.server_name}";
  #     wopi_allowlist = lib.concatStringsSep "," [
  #       "127.0.0.1"
  #       "::1"
  #     ];
  #   in
  #   {
  #     wantedBy = [ "multi-user.target" ];
  #     after = [
  #       "nextcloud-setup.service"
  #       "coolwsd.service"
  #     ];
  #     requires = [ "coolwsd.service" ];
  #     script = ''
  #       ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_url --value ${lib.escapeShellArg wopi_url}
  #       ${occ}/bin/nextcloud-occ config:app:set richdocuments public_wopi_url --value ${lib.escapeShellArg public_wopi_url}
  #       ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist --value ${lib.escapeShellArg wopi_allowlist}
  #       ${occ}/bin/nextcloud-occ richdocuments:setup
  #     '';
  #     serviceConfig = {
  #       Type = "oneshot";
  #     };
  #   };
  sops.secrets."password" = {
    restartUnits = [ "nextcloud-setup.service" ];
    owner = "nextcloud";
  };

  sops.secrets."nextcloud/oidc-secret" = {
    restartUnits = [ "nextcloud-setup.service" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      owncloud = {
        rule = "Host(`cloud.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        # middlewares = [
        #   "nextcloud@file"
        # ];
        service = "owncloud";
      };
    };
    # middlewares.nextcloud = {
    #   headers.customRequestHeaders.Host = "${cfg.hostName}";
    # };
    services = {
      owncloud.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}"; } ];
      };
    };
  };
}
