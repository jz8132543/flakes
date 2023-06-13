{
  config,
  pkgs,
  lib,
  ...
}: let
  element-web-config = pkgs.runCommand "element-web-config" {} ''
    mkdir -p $out
    "${pkgs.jq}/bin/jq" -s ".[0] * .[1]" \
      "${pkgs.element-web}/config.json" \
      ${/${config.lib.self.path}/conf/synapse/mixin-config.json} \
      > $out/config.json
  '';
in
  lib.mkMerge [
    # matrix-synapse
    {
      sops.secrets = {
        "matrix/mail" = {};
        "matrix/signing-key" = {owner = "matrix-synapse";};
        "matrix/oidc-secret" = {};
        "b2/keyID" = {};
        "b2/applicationKey" = {};
      };
      services.matrix-synapse = {
        enable = true;
        withJemalloc = true;
        plugins = [
          config.nur.repos.linyinfeng.synapse-s3-storage-provider
        ];
        settings = {
          server_name = "dora.im";
          public_baseurl = "https://m.dora.im";
          admin_contact = "mailto:i@dora.im";
          signing_key_path = config.sops.secrets."matrix/signing-key".path;

          database = {
            name = "psycopg2";
            args = {
              # local database
              user = "synapse";
              database = "synapse";
              host = "postgres.dora.im";
            };
          };

          # trust the default key server matrix.org
          suppress_key_server_warning = true;

          enable_search = true;
          dynamic_thumbnails = true;
          allow_public_rooms_over_federation = true;

          enable_registration = true;
          registration_requires_token = true;
          registrations_require_3pid = [
            "email"
          ];

          media_retention = {
            # no retention for local media to keep stickers
            # local_media_lifetime = "180d";
            remote_media_lifetime = "14d";
          };

          listeners = [
            {
              bind_addresses = ["127.0.0.1"];
              port = config.ports.matrix;
              tls = false;
              type = "http";
              x_forwarded = true;
              resources = [
                {
                  compress = true;
                  names = ["client" "federation"];
                }
              ];
            }
          ];
        };
        extraConfigFiles = [
          # configurations with secrets
          config.sops.templates."synapse-extra-config".path
        ];
      };

      sops.templates."synapse-extra-config" = {
        owner = "matrix-synapse";
        content = builtins.toJSON {
          email = {
            smtp_host = "${config.lib.self.data.mail.smtp}";
            smtp_user = "matrix@dora.im";
            notif_from = "matrix@dora.im";
            force_tls = true;
            smtp_pass = config.sops.placeholder."matrix/mail";
          };
          oidc_providers = [
            {
              idp_id = "keycloak";
              idp_name = "keycloak";
              issuer = "https://sso.dora.im/realms/users";
              client_id = "synapse";
              client_secret = config.sops.placeholder."matrix/oidc-secret";
              scopes = ["openid" "profile" "email"];
              allow_existing_users = true;
              user_mapping_provider.config = {
                confirm_localpart = true;
                localpart_template = "{{ user.preferred_username }}";
                display_name_template = "{{ user.name }}";
                email_template = "{{ user.email }}";
              };
            }
          ];
          media_storage_providers = [
            # as backup of all local media
            {
              module = "s3_storage_provider.S3StorageProviderBackend";
              store_local = true;
              store_remote = true;
              store_synchronous = true;
              config = {
                bucket = config.lib.self.data.matrix.media.name;
                region_name = config.lib.self.data.matrix.media.region;
                endpoint_url = "https://${config.lib.self.data.matrix.media.host}";
                access_key_id = config.sops.placeholder."b2/keyID";
                secret_access_key = config.sops.placeholder."b2/applicationKey";
              };
            }
          ];
        };
      };
      environment.systemPackages = [
        config.nur.repos.linyinfeng.synapse-s3-storage-provider
      ];
    }
    # reverse proxy
    {
      services.traefik.dynamicConfigOptions.http = {
        routers = {
          matrix = {
            rule = "Host(`m.dora.im`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`))";
            entryPoints = ["https"];
            service = "matrix";
            priority = 99;
          };
          element = {
            rule = "Host(`m.dora.im`)";
            entryPoints = ["https"];
            service = "element";
          };
          matrix-admin = {
            rule = "Host(`admin.m.dora.im`)";
            entryPoints = ["https"];
            service = "matrix-admin";
          };
        };
        services = {
          matrix.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://localhost:${toString config.ports.matrix}";}];
          };
          element.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://m.dora.im:${toString config.ports.nginx}";}];
          };
          matrix-admin.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://admin.m.dora.im:${toString config.ports.nginx}";}];
          };
        };
      };
      services.nginx = {
        enable = true;
        defaultHTTPListenPort = config.ports.nginx;
        virtualHosts."m.*" = {
          locations."/" = {
            root = pkgs.element-web;
          };
          locations."/config.json" = {
            root = element-web-config;
          };
        };
        virtualHosts."admin.m.*" = {
          locations."/" = {
            root = pkgs.synapse-admin;
          };
        };
      };
    }
  ]
