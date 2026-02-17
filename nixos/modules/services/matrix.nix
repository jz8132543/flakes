# https://github.com/xddxdd/nixos-config/blob/0efc32d005bfd4bd67412be008673e90af7219cd/nixos/common-apps/nginx/vhost-matrix-element/default.nix
{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  elementConfig = builtins.toJSON {
    default_server_config = {
      server = {
        "m.server" = "m.dora.im:443";
      };
      client = {
        "m.server"."base_url" = "https://m.dora.im";
        "m.homeserver"."base_url" = "https://m.dora.im";
        "m.identity_server"."base_url" = "https://vector.im";
        "org.matrix.msc3575.proxy"."url" = "https://m.dora.im";
      };
    };
    disable_custom_urls = true;
    disable_guests = true;
    disable_login_language_selector = false;
    disable_3pid_login = true;
    default_country_code = "US";
    show_labs_settings = true;
    default_federate = true;
    default_theme = "dark";
    room_directory.servers = [
      "matrix.org"
      "nixos.org"
      "dora.im"
    ];
    embedded_pages.login_for_welcome = true;
    setting_defaults = {
      "UIFeature.feedback" = false;
      "UIFeature.registration" = false;
      "UIFeature.passwordReset" = false;
      "UIFeature.deactivate" = false;
      "UIFeature.TimelineEnableRelativeDates" = false;
    };
  };

  elementConfigPath = pkgs.stdenvNoCC.mkDerivation {
    name = "element-config";
    dontUnpack = true;
    postInstall = ''
      mkdir -p $out
      ${lib.getExe pkgs.jq} -s -c '.[0] * $conf' "${pkgs.element-web}/config.json" --argjson "conf" '${elementConfig}' > "$out/config.json"
    '';
  };
in
lib.mkMerge [
  # matrix-synapse
  {
    sops.secrets = {

      "matrix/signing-key" = {
        owner = "matrix-synapse";
      };
      "matrix/oidc-secret" = { };
      "matrix/registration_shared_secret" = { };
      "matrix/turn_shared_secret" = {
        mode = "0440";
        owner = "matrix-synapse";
        group = "acme";
      };
      # "b2_synapse_media_key_id".sopsFile = config.sops-file.get "terraform/common.yaml";
      # "b2_synapse_media_access_key".sopsFile = config.sops-file.get "terraform/common.yaml";
    };
    services.matrix-synapse = {
      enable = true;
      withJemalloc = true;
      # plugins = with pkgs.python3.pkgs;
      #   [authlib]
      #   ++ [
      #     #   pkgs.nur.repos.linyinfeng.synapse-s3-storage-provider
      #   ];
      settings = {
        server_name = "dora.im";
        public_baseurl = "https://m.dora.im";
        admin_contact = "mailto:i@dora.im";
        report_stats = true;
        enable_metrics = true;
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

        enable_registration = false;
        password_config.enabled = false;
        # registration_requires_token = true;
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
            bind_addresses = [ "127.0.0.1" ];
            port = config.ports.matrix;
            tls = false;
            type = "http";
            x_forwarded = true;
            resources = [
              {
                compress = true;
                names = [
                  "client"
                  "federation"
                ];
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
            scopes = [
              "openid"
              "profile"
              "email"
            ];
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
          "turn:nue0.dora.im:3479?transport=udp"
          "turn:nue0.dora.im:3479?transport=tcp"
          "turns:nue0.dora.im:5349?transport=udp"
          "turns:nue0.dora.im:5349?transport=tcp"
          "turns:hkg0.dora.im:5349?transport=udp"
          "turns:hkg0.dora.im:5349?transport=tcp"
          "turns:fra1.dora.im:5349?transport=udp"
          "turns:fra1.dora.im:5349?transport=tcp"
          "turns:hkg4.dora.im:5349?transport=udp"
          "turns:hkg4.dora.im:5349?transport=tcp"
        ];
        turn_user_lifetime = "1h";
        turn_allow_guests = false;
        experimental_features = {
          # Room summary api
          msc3266_enabled = true;
          # Removing account data
          msc3391_enabled = true;
          # Thread notifications
          msc3773_enabled = true;
          # Remotely toggle push notifications for another client
          msc3881_enabled = true;
          # Remotely silence local notifications
          msc3890_enabled = true;
        };
        rc_admin_redaction = {
          per_second = 1000;
          burst_count = 10000;
        };
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
          smtp_user = "noreply@dora.im";
          notif_from = "noreply@dora.im";
          force_tls = true;
          smtp_pass = config.sops.placeholder."mail/noreply";
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
      # pkgs.nur.repos.linyinfeng.synapse-s3-storage-provider
    ];
    systemd.services."matrix-synapse" = {
      after = [
        "postgresql.service"
        "tailscaled.service"
      ];
      serviceConfig.Restart = lib.mkForce "always";
    };
  }
  # reverse proxy
  {
    services.traefik.proxies = {
      matrix = {
        rule = "Host(`m.dora.im`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`) || PathPrefix(`/.well-known`))";
        target = "http://localhost:${toString config.ports.matrix}";
      };
      element = {
        rule = "Host(`m.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
      matrix-admin = {
        rule = "Host(`admin.m.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
    };
    services.nginx = {
      enable = true;
      defaultHTTPListenPort = config.ports.nginx;
      virtualHosts."m.*" = {
        root = pkgs.element-web;
        locations = {
          "/" = {
            index = "index.html index.htm";
            tryFiles = "$uri $uri/ =404";
          };
          # "= /config.json".root = "${elementConfigPath}/config.json";
          "= /config.json".root = "${elementConfigPath}";
        };
        # locations."/" = {
        #   root = pkgs.element-web;
        # };
        # locations."/config.json" = {
        #   root = element-web-config;
        # };
      };
      virtualHosts."admin.m.*" = {
        locations."/" = {
          root = pkgs.synapse-admin-etkecc;
        };
      };
    };
  }
]
