# https://github.com/xddxdd/nixos-config/blob/0efc32d005bfd4bd67412be008673e90af7219cd/nixos/common-apps/nginx/vhost-matrix-element/default.nix
{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  pkgs,
  lib,
  nixosModules,
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
{
  imports = [ (import ./mas.nix { inherit PG nixosModules; }) ];

  config = lib.mkMerge [
    {
      sops.secrets = {
        "matrix/signing-key" = {
          owner = "matrix-synapse";
        };
        "matrix/oidc-secret" = { };
        "matrix/registration_shared_secret" = {
          mode = "0440";
          owner = "matrix-synapse";
          group = "matrix-authentication-service";
        };
        "matrix/turn_shared_secret" = {
          mode = "0440";
          owner = "matrix-synapse";
          group = "acme";
        };
      };

      services.matrix-synapse = {
        enable = true;
        withJemalloc = true;
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
              user = "synapse";
              database = "synapse";
              host = PG;
            };
          };

          suppress_key_server_warning = true;
          enable_search = true;
          dynamic_thumbnails = true;
          allow_public_rooms_over_federation = true;

          enable_registration = false;
          password_config.enabled = false;

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

          rc_admin_redaction = {
            per_second = 1000;
            burst_count = 10000;
          };
        };
        extraConfigFiles = [
          config.sops.templates."synapse-extra-config".path
        ];
      };

      sops.templates."synapse-extra-config" = {
        owner = "matrix-synapse";
        content = builtins.toJSON {
          experimental_features = {
            msc3266_enabled = true;
            msc3391_enabled = true;
            msc3773_enabled = true;
            msc3881_enabled = true;
            msc3890_enabled = true;
            msc3861 = {
              enabled = true;
              issuer = "https://m.dora.im/";
              client_id = "synapse";
              client_auth_method = "client_secret_basic";
              client_secret = config.sops.placeholder."matrix/registration_shared_secret";
              admin_token = config.sops.placeholder."matrix/registration_shared_secret";
              account_management_url = "https://m.dora.im/account";
            };
          };
          email = {
            smtp_host = "${config.lib.self.data.mail.smtp}";
            smtp_user = "services@dora.im";
            notif_from = "services@dora.im";
            force_tls = true;
            smtp_pass = config.sops.placeholder."mail/services";
          };
          turn_shared_secret = config.sops.placeholder."matrix/turn_shared_secret";
        };
      };

      environment.systemPackages = [ ];

      systemd.services."matrix-synapse" = {
        after = [
          "postgresql.service"
          "tailscaled.service"
        ];
        serviceConfig.Restart = lib.mkForce "always";
      };
    }

    {
      services.traefik.proxies = {
        matrix = {
          rule = "Host(`m.dora.im`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`))";
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
            "= /config.json".root = "${elementConfigPath}";
          };
        };
        virtualHosts."admin.m.*" = {
          locations."/" = {
            root = pkgs.ketesa;
          };
        };
      };
    }
  ];
}
