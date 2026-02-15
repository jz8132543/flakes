# https://github.com/opencloud-eu/opencloud/blob/main/deployments/examples/opencloud_full/keycloak.yml
{
  config,
  pkgs,
  ...
}:

let
  configDir = "/var/lib/opencloud/config";
  dataDir = "/var/lib/opencloud/data";

  containerBackendName = config.virtualisation.oci-containers.backend;
  containerBackend = pkgs."${containerBackendName}" + "/bin/" + containerBackendName;
in
{
  virtualisation.oci-containers.containers = {
    opencloud = {
      autoStart = true;
      image = "opencloudeu/opencloud";
      ports = [ "${toString config.ports.opencloud}:9200" ];
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "${configDir}:/etc/opencloud"
        "${./csp.yaml}:/etc/opencloud/csp.yaml"
        "${./proxy.yaml}:/etc/opencloud/proxy.yaml"
        "${./app-registry.yaml}:/etc/opencloud/app-registry.yaml"
        "${dataDir}:/var/lib/opencloud"
      ];

      environment = {
        # PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
        # PROXY_AUTOPROVISION_ACCOUNTS = false;
        # OC_OIDC_ISSUER = "https://sso.dora.im/realms/users";
        # PROXY_OIDC_REWRITE_WELLKNOWN = true;
        # PROXY_USER_OIDC_CLAIM = "preferred_username";
        # WEB_OPTION_ACCOUNT_EDIT_LINK_HREF = "https://sso.dora.im/realms/users/account";
        # OC_ADMIN_USER_ID = "i";
        # OC_EXCLUDE_RUN_SERVICES = "idp,idm";
        # GRAPH_ASSIGN_DEFAULT_USER_ROLE = false;
        # GRAPH_USERNAME_MATCH = "none";
        # SETTINGS_SETUP_DEFAULT_ASSIGNMENTS = false;
        # IDM_CREATE_DEMO_USERS = false;
        # KEYCLOAK_DOMAIN = "sso.dora.im";
        # KEYCLOAK_REALM = "users";
        # OC_OIDC_CLIENT_ID = "opencloud";

        PROXY_TLS = "false";
        PROXY_HTTP_ADDR = "0.0.0.0:9200";
        START_ADDITIONAL_SERVICES = "notifications";

        OC_INSECURE = "false";
        OC_URL = "https://cloud.${config.networking.domain}";
        OC_LOG_LEVEL = "info";

        STORAGE_USERS_POSIX_WATCH_FS = "true";
        GATEWAY_GRPC_ADDR = "0.0.0.0:9142";
        MICRO_REGISTRY_ADDRESS = "127.0.0.1:9233";
        NATS_NATS_HOST = "0.0.0.0";
        NATS_NATS_PORT = "9233";

        #Tika
        SEARCH_EXTRACTOR_TYPE = "tika";
        SEARCH_EXTRACTOR_TIKA_TIKA_URL = "http://opencloud-tika:9998";
        FRONTEND_FULL_TEXT_SEARCH_ENABLED = "true";
      };

      environmentFiles = [ config.sops.templates."opencloud-env".path ];

      entrypoint = "/bin/sh";
      extraOptions = [ "--network=opencloud-bridge" ];
      cmd = [
        "-c"
        "opencloud init | true; opencloud server"
      ];
      log-driver = "journald";
    };

    opencloud-tika = {
      autoStart = true;
      image = "apache/tika";
      extraOptions = [ "--network=opencloud-bridge" ];
    };
  };

  # Network creation
  systemd.services.init-opencloud-network = {
    description = "Create the network bridge for opencloud.";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Put a true at the end to prevent getting non-zero return code, which will
      # crash the whole service.
      check=$(${containerBackend} network ls | ${pkgs.gnugrep}/bin/grep "opencloud-bridge" || true)
      if [ -z "$check" ]; then
        ${containerBackend} network create opencloud-bridge
      else
           echo "opencloud-bridge already exists"
       fi
    '';
  };
  sops.templates."opencloud-env" = {
    content = ''
      PROXY_ROLE_ASSIGNMENT_DRIVER=oidc
      PROXY_AUTOPROVISION_ACCOUNTS=false
      OC_OIDC_ISSUER=https://sso.dora.im/realms/users
      PROXY_OIDC_REWRITE_WELLKNOWN=true
      PROXY_USER_OIDC_CLAIM=preferred_username
      WEB_OPTION_ACCOUNT_EDIT_LINK_HREF=https://sso.dora.im/realms/users/account
      OC_ADMIN_USER_ID=i
      OC_EXCLUDE_RUN_SERVICES=idp,idm
      GRAPH_ASSIGN_DEFAULT_USER_ROLE=false
      GRAPH_USERNAME_MATCH=none
      SETTINGS_SETUP_DEFAULT_ASSIGNMENTS=false
      IDM_CREATE_DEMO_USERS=false
      KEYCLOAK_DOMAIN=sso.dora.im
      KEYCLOAK_REALM=users
      OC_OIDC_CLIENT_ID=opencloud
    '';
  };

  # Expose ports for container
  networking.firewall = {
    allowedTCPPorts = [ config.ports.opencloud ];
  };

  systemd.tmpfiles.settings.opencloud = {
    "${dataDir}" = {
      d = {
        mode = "0777";
        user = "root";
      };
    };
    "${configDir}" = {
      d = {
        mode = "0777";
        user = "root";
      };
    };
  };
  services.traefik.proxies.opencloud = {
    rule = "Host(`cloud.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.opencloud}";
  };
}
