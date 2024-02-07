{PG ? "postgres.dora.im", ...}: {
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
        "matrix/registration_shared_secret" = {};
        "matrix/turn_shared_secret" = {
          mode = "0440";
          owner = "matrix-synapse";
          group = "acme";
        };
      };
      sops.secrets."b2_synapse_media_key_id".sopsFile = config.sops-file.get "terraform/common.yaml";
      sops.secrets."b2_synapse_media_access_key".sopsFile = config.sops-file.get "terraform/common.yaml";
      services.matrix-synapse = {
        enable = true;
        withJemalloc = true;
        # plugins = with pkgs.python3.pkgs;
        #   [authlib]
        #   ++ [
        #     #   config.nur.repos.linyinfeng.synapse-s3-storage-provider
        #   ];
        settings = {
          server_name = "dora.im";
          public_baseurl = "https://m.dora.im";
          admin_contact = "mailto:i@dora.im";
          signing_key_path = config.sops.secrets."matrix/signing-key".path;
          serve_server_wellknown = true;

          database = {
            name = "psycopg2";
            args = {
              # local database
              user = "synapse";
              database = "synapse";
              host = PG;
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
            # remote_media_lifetime = "14d";
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
          oidc_providers = [
            {
              idp_id = "keycloak";
              idp_name = "keycloak";
              issuer = "https://sso.dora.im/realms/users";
              client_id = "synapse";
              client_secret = config.sops.secrets."matrix/oidc-secret".path;
              scopes = ["openid" "profile" "email"];
              allow_existing_users = true;
              backchannel_logout_enabled = true;
              user_mapping_provider.config = {
                confirm_localpart = true;
                localpart_template = "{{ user.preferred_username }}";
                display_name_template = "{{ user.name }}";
                email_template = "{{ user.email }}";
              };
            }
          ];
          turn_uris = [
            "turns:shg0.dora.im?transport=udp"
            "turns:shg0.dora.im?transport=tcp"
            "turns:tippy.dora.im?transport=udp"
            "turns:tippy.dora.im?transport=tcp"
          ];
          turn_user_lifetime = "1h";
          turn_allow_guests = false;
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
          # media_storage_providers = [
          #   # as backup of all local media
          #   {
          #     module = "s3_storage_provider.S3StorageProviderBackend";
          #     store_local = true;
          #     store_remote = true;
          #     store_synchronous = true;
          #     config = {
          #       bucket = config.lib.self.data.matrix.media.name;
          #       region_name = config.lib.self.data.matrix.media.region;
          #       endpoint_url = "https://${config.lib.self.data.matrix.media.host}";
          #       access_key_id = config.sops.placeholder."b2_synapse_media_key_id";
          #       secret_access_key = config.sops.placeholder."b2_synapse_media_access_key";
          #     };
          #   }
          # ];
          # registration_shared_secret = config.sops.placeholder."matrix/registration_shared_secret";
          turn_shared_secret = config.sops.placeholder."matrix/turn_shared_secret";
        };
      };
      environment.systemPackages = [
        config.nur.repos.linyinfeng.synapse-s3-storage-provider
      ];
      systemd.services."matrix-synapse" = {
        after = ["postgresql.service" "tailscaled.service"];
        serviceConfig.Restart = lib.mkForce "always";
      };
    }
    #STUN
    {
      services.coturn = {
        enable = true;
        use-auth-secret = true;
        static-auth-secret-file = config.sops.secrets."matrix/turn_shared_secret".path;
        realm = "${config.networking.fqdn}";
        min-port = 49152;
        max-port = 49262;
        no-cli = true;
        cert = "${config.security.acme.certs."main".directory}/fullchain.pem";
        pkey = "${config.security.acme.certs."main".directory}/key.pem";
        no-tcp-relay = true;
        extraConfig = ''
          listening-ip=0.0.0.0
          userdb=/var/lib/coturn/turnserver.db
          no-tlsv1
          no-tlsv1_1
          no-rfc5780
          no-stun-backward-compatibility
          response-origin-only-with-rfc5780
          no-multicast-peers
        '';
      };
      systemd.services.coturn.serviceConfig.StateDirectory = "coturn";
      systemd.services.coturn.serviceConfig.Group = lib.mkForce "acme";
    }
    # reverse proxy
    {
      services.traefik.dynamicConfigOptions.http = {
        routers = {
          matrix = {
            rule = "Host(`m.dora.im`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`) || PathPrefix(`/.well-known`))";
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
            servers = [{url = "http://localhost:${toString config.ports.nginx}";}];
          };
          matrix-admin.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://localhost:${toString config.ports.nginx}";}];
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
