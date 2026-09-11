{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.matrix;
  matrixRtcHosts = cfg.rtcHosts;

  elementCallConfig = builtins.toJSON {
    default_server_config = {
      "m.homeserver" = {
        base_url = "https://m.dora.im";
        server_name = "dora.im";
      };
    };
    media_quality = {
      video_codec = "vp9";
      video = {
        max_resolution = 4320;
        max_framerate = 60;
        max_bitrate = 50000000;
      };
      screen_share = {
        max_resolution = 4320;
        max_framerate = 60;
        max_bitrate = 50000000;
      };
    };
  };

  elementCallConfigPath = pkgs.writeText "element-call-config.json" elementCallConfig;

  elementConfig = builtins.toJSON {
    default_server_config = {
      "m.homeserver" = {
        base_url = "https://m.dora.im";
        server_name = "dora.im";
      };
      "m.identity_server" = {
        base_url = "https://vector.im";
      };
    };
    disable_custom_urls = true;
    disable_guests = true;
    disable_login_language_selector = false;
    disable_3pid_login = true;
    default_country_code = "CN";
    show_labs_settings = true;
    default_federate = true;
    default_theme = "dark";
    room_directory.servers = [
      "dora.im"
      "matrix.org"
      "nixos.org"
    ];
    embedded_pages.login_for_welcome = true;
    element_call = {
      brand = "Element Call";
      use_exclusively = true;
    };
    features = {
      feature_group_calls = true;
      feature_element_call_video_rooms = true;
      feature_latex_maths = true;
      feature_pinning = true;
      feature_custom_status = true;
      feature_favourite_messages = true;
      feature_voice_broadcast = true;
      feature_spotlight = true;
      feature_wysiwyg_composer = true;
      feature_jump_to_date = true;
      feature_location_sharing = true;
      feature_render_unconfirmed_events = true;
      feature_ask_to_join = true;
      feature_mjolnir = true;
      feature_threads = true;
      feature_sliding_sync = true;
    };
    setting_defaults = {
      breadcrumbs = true;
      "Pill.shouldShowPillAvatar" = true;
      "MessageComposerInput.suggestEmoji" = true;
      "MessageComposerInput.showStickersButton" = true;
      urlPreviewsEnabled = true;
      alwaysShowTimestamps = true;
      "UIFeature.feedback" = false;
      "UIFeature.registration" = false;
      "UIFeature.passwordReset" = false;
      "UIFeature.deactivate" = false;
      "UIFeature.TimelineEnableRelativeDates" = false;
    };
    media_quality = {
      video_codec = "vp9";
      video = {
        max_resolution = 4320;
        max_framerate = 60;
        max_bitrate = 50000000;
      };
      screen_share = {
        max_resolution = 4320;
        max_framerate = 60;
        max_bitrate = 50000000;
      };
    };
  };

  synapseClientId = "01J0YJ8F7Q8X2V6K9M4T1A3BCD";

  elementConfigPath = pkgs.stdenvNoCC.mkDerivation {
    name = "element-config";
    dontUnpack = true;
    postInstall = ''
      mkdir -p $out
      ${lib.getExe pkgs.jq} -s -c '.[0] * $conf' "${pkgs.element-web}/config.json" --argjson "conf" '${elementConfig}' > "$out/config.json"
    '';
  };

  enabledMatrixRtcHosts =
    let
      currentHost = config.networking.hostName;
      otherHosts = lib.filter (hostName: hostName != currentHost) matrixRtcHosts;
    in
    lib.sort (a: b: a < b) (
      lib.unique (lib.optional config.services.matrix-rtc.enable currentHost ++ otherHosts)
    );

  matrixRtcFoci = map (hostName: {
    type = "livekit";
    livekit_service_url = "https://${hostName}.dora.im/livekit/jwt";
  }) enabledMatrixRtcHosts;

  matrixClientWellKnown = builtins.toJSON {
    "m.homeserver" = {
      base_url = "https://m.dora.im";
    };
    "org.matrix.msc2965.authentication" = {
      issuer = "https://m.dora.im/";
      account = "https://m.dora.im/account";
    };
    "org.matrix.msc4143.rtc_foci" = matrixRtcFoci;
  };
in
{
  options.services.matrix.databaseHost = lib.mkOption {
    type = lib.types.str;
    default = "postgres.mag";
    description = "PostgreSQL host for Synapse.";
  };

  options.services.matrix.rtcHosts = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default =
      config.lib.self.data.matrix.rtcHosts or [
        "nue0"
        "sjc0"
      ];
    description = "Matrix RTC hosts";
  };

  config = {
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
    };

    services.matrix-synapse = {
      enable = true;
      withJemalloc = true;
      extras = [ "oidc" ];
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
            host = cfg.databaseHost;
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
        registration_shared_secret = config.sops.placeholder."matrix/registration_shared_secret";
        macaroon_secret_key = config.sops.placeholder."matrix/registration_shared_secret";
        experimental_features = {
          msc3266_enabled = true;
          msc3391_enabled = true;
          msc3773_enabled = true;
          msc3881_enabled = true;
          msc3890_enabled = true;
          msc4143_enabled = true;
        };
        matrix_authentication_service = {
          enabled = true;
          endpoint = "http://localhost:${toString config.ports.mas}";
          issuer = "https://m.dora.im/";
          client_id = synapseClientId;
          client_auth_method = "client_secret_basic";
          client_secret = config.sops.placeholder."matrix/registration_shared_secret";
          secret = config.sops.placeholder."matrix/registration_shared_secret";
          admin_token = config.sops.placeholder."matrix/registration_shared_secret";
          account_management_url = "https://m.dora.im/account";
        };
        matrix_rtc = {
          transports = matrixRtcFoci;
        };
        email = {
          smtp_host = "${config.lib.self.data.mail.smtp}";
          smtp_user = "services@dora.im";
          notif_from = "services@dora.im";
          force_tls = true;
          smtp_pass = config.sops.placeholder."mail/services";
        };
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

    services.traefik.proxies = {
      matrix = {
        rule = "Host(`m.dora.im`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`))";
        target = "http://localhost:${toString config.ports.matrix}";
      };
      element = {
        rule = "Host(`m.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
      element-call = {
        rule = "Host(`call.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
      matrix-admin = {
        rule = "Host(`admin.m.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
      doraim = {
        rule = "Host(`dora.im`) && PathPrefix(`/.well-known`)";
        target = "http://localhost:${toString config.ports.nginx}";
        priority = 100;
      };
      mta-sts = {
        rule = "Host(`mta-sts.dora.im`)";
        target = "http://localhost:${toString config.ports.nginx}";
      };
    };

    services.nginx = {
      enable = true;
      defaultHTTPListenPort = config.ports.nginx;
      virtualHosts."call.dora.im" = {
        root = pkgs.element-call;
        locations = {
          "/" = {
            index = "index.html";
            tryFiles = "$uri $uri/ /index.html =404";
          };
          "= /config.json".alias = elementCallConfigPath;
        };
      };
      virtualHosts."m.*" = {
        root = pkgs.element-web;
        locations = {
          "/" = {
            index = "index.html index.htm";
            tryFiles = "$uri $uri/ =404";
          };
          "= /config.json".root = "${elementConfigPath}";
          "= /widgets/element-call/config.json".alias = elementCallConfigPath;
          "/.well-known/matrix/server".extraConfig = ''
            default_type application/json;
            return 200 '{ "m.server": "m.dora.im:443" }';
          '';
          "/.well-known/matrix/client".extraConfig = ''
            add_header Access-Control-Allow-Origin '*';
            default_type application/json;
            return 200 '${matrixClientWellKnown}';
          '';
        };
      };
      virtualHosts."admin.m.*" = {
        locations."/" = {
          root = pkgs.ketesa;
        };
      };
      virtualHosts."dora.im" = {
        locations."/.well-known/matrix/server".extraConfig = ''
          default_type application/json;
          return 200 '{ "m.server": "m.dora.im:443" }';
        '';
        locations."/.well-known/matrix/client".extraConfig = ''
          add_header Access-Control-Allow-Origin '*';
          default_type application/json;
          return 200 '${matrixClientWellKnown}';
        '';
        locations."/.well-known/host-meta".extraConfig = ''
          return 301 https://zone.dora.im$request_uri;
        '';
        locations."/.well-known/webfinger".extraConfig = ''
          return 301 https://zone.dora.im$request_uri;
        '';
        locations."=/.well-known/autoconfig/mail/config-v1.1.xml".alias =
          pkgs.writeText "config-v1.1.xml" ''
            <?xml version="1.0" encoding="UTF-8"?>

            <clientConfig version="1.1">
              <emailProvider id="dora.im">
                <domain>dora.im</domain>
                <displayName>Doraemon Mail</displayName>
                <displayShortName>Doraemon</displayShortName>
                <incomingServer type="imap">
                  <hostname>glacier.mxrouting.net</hostname>
                  <port>993</port>
                  <socketType>SSL</socketType>
                  <authentication>password-cleartext</authentication>
                  <username>%EMAILADDRESS%</username>
                </incomingServer>
                <outgoingServer type="smtp">
                  <hostname>glacier.mxrouting.net</hostname>
                  <port>465</port>
                  <socketType>SSL</socketType>
                  <authentication>password-cleartext</authentication>
                  <username>%EMAILADDRESS%</username>
                </outgoingServer>
              </emailProvider>
            </clientConfig>
          '';
      };
      virtualHosts."dora.im".locations."/".extraConfig = ''
        return 301 https://nue0.dora.im/home/;
      '';
      virtualHosts."mta-sts.dora.im".locations."=/.well-known/mta-sts.txt".alias =
        pkgs.writeText "mta-sts.txt" ''
          version: STSv1
          mode: enforce
          mx: *.dora.im
          mx: *.mxrouting.net
          max_age: 86400
        '';
    };

    networking.firewall.allowedTCPPorts = [ 1688 ];
    systemd.services.vlmcsd = {
      description = "vlmcsd server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "3";
        ExecStart = "${pkgs.nur.repos.linyinfeng.vlmcsd}/bin/vlmcsd -D -v";
        DynamicUser = true;
      };
    };
  };
}
