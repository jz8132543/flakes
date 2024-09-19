{
  PG ? "postgres.mag",
  ...
}:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  akkconfig = ''
    import Config
    config :pleroma, :instance,
      allow_relay: true,
      cleanup_attachments: true,
      description: "Doraemon's akkoma server",
      email: "i@dora.im",
      healthcheck: true,
      invites_enabled: true,
      limit: 69420,
      limit_to_local_content: :unauthenticated,
      max_account_fields: 100,
      max_pinned_statuses: 10,
      name: "Akkoma",
      notify_email: "i@dora.im",
      registrations_open: false,
      remote_limit: 100_000,
      static_dir: "${pkgs.pleroma-static}"
    config :pleroma, Pleroma.Repo,
      adapter: Ecto.Adapters.Postgres,
      database: "pleroma",
      hostname: "${PG}",
      username: "pleroma"
    config :pleroma, :frontend_configurations,
      pleroma_fe: %{
        loginMethod: "token"
      },
      masto_fe: %{
        showInstanceSpecificPanel: true
      }
    config :pleroma, :frontends,
      primary: %{"name" => "akkoma-fe", "ref" => "stable"},
      admin: %{"name" => "admin-fe", "ref" => "stable"},
      mastodon: %{"name" => "mastodon-fe", "ref" => "stable"},
      swagger: %{"name" => "swagger-ui", "ref" => "stable"}

    config :logger,
      backends: [ {ExSyslogger, :ex_syslogger}, :console ],
      level: :debug

    config :logger, :ex_syslogger,
      level: :debug,
      ident: "pleroma",
      format: "$metadata[$level] $message"

    config :logger, :console,
      level: :debug,
      format: "\n$time $metadata[$level] $message\n",
      metadata: [:request_id]

    config :pleroma, configurable_from_database: false
    config :pleroma, :media_proxy, enabled: false
    config :pleroma, :mrf, policies: [Pleroma.Web.ActivityPub.MRF.SimplePolicy], transparency: false
    config :pleroma, Pleroma.Web.WebFinger, domain: "dora.im"
  '';
in
{
  services.pleroma = {
    enable = true;
    package = pkgs.akkoma;
    user = "akkoma";
    group = "akkoma";

    configs = [ akkconfig ];
    secretConfigFile = config.sops.templates."akkoma".path;
  };

  sops.templates."akkoma" = {
    owner = config.services.pleroma.user;
    content = ''
      import Config
      # keycloak
      keycloak_url = "https://sso.dora.im/"
      config :ueberauth, Ueberauth.Strategy.Keycloak.OAuth,
        client_id: "pleroma",
        client_secret: "${config.sops.placeholder."pleroma/oidc-secret"}",
        site: keycloak_url,
        authorize_url: "#{keycloak_url}/realms/users/protocol/openid-connect/auth",
        token_url: "#{keycloak_url}/realms/users/protocol/openid-connect/token",
        userinfo_url: "#{keycloak_url}/realms/users/protocol/openid-connect/userinfo",
        token_method: :post
      config :ueberauth, Ueberauth,
        providers: [
          keycloak: {Ueberauth.Strategy.Keycloak, [default_scope: "openid profile email"]}
        ]
      config :pleroma, :auth, oauth_consumer_strategies: ["keycloak:ueberauth_keycloak_strategy", "keycloak"]
      # s3
      config :pleroma, Pleroma.Upload, proxy_remote: true, uploader: Pleroma.Uploaders.S3
      config :pleroma, Pleroma.Uploaders.S3, bucket: "${config.lib.self.data.pleroma.media.name}"
      config :ex_aws, :s3,
        access_key_id: "${config.sops.placeholder."b2_pleroma_media_key_id"}",
        host: "${config.lib.self.data.pleroma.media.host}",
        secret_access_key: "${config.sops.placeholder."b2_pleroma_media_access_key"}"
      # Configure web push notifications
      config :web_push_encryption, :vapid_details,
        subject: "mailto:i@dora.im",
        public_key: "${config.sops.placeholder."pleroma/PUSH_PUBLIC_KEY"}",
        private_key: "${config.sops.placeholder."pleroma/PUSH_PRIVATE_KEY"}"
      config :pleroma, Pleroma.Web.Endpoint,
        http: [ip: {127, 0, 0, 1}, port: 4000],
        url: [host: "zone.dora.im", port: 443, scheme: "https"],
        secret_key_base: "${config.sops.placeholder."pleroma/SECRET_KEY"}",
        signing_salt: "${config.sops.placeholder."pleroma/SIGNING_SALT"}",
        extra_cookie_attrs: ["SameSite=Lax"]
    '';
  };

  sops.secrets = {
    "pleroma/oidc-secret" = { };
    "pleroma/PUSH_PUBLIC_KEY" = { };
    "pleroma/PUSH_PRIVATE_KEY" = { };
    "pleroma/SECRET_KEY" = { };
    "pleroma/SIGNING_SALT" = { };
  };

  sops.secrets."b2_pleroma_media_key_id" = {
    sopsFile = config.sops-file.get "terraform/common.yaml";
    restartUnits = [ "akkoma.service" ];
  };

  sops.secrets."b2_pleroma_media_access_key" = {
    sopsFile = config.sops-file.get "terraform/common.yaml";
    restartUnits = [ "akkoma.service" ];
  };

  systemd.services.pleroma = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "always";
    # https://github.com/NixOS/nixpkgs/issues/170805
    environment.RELEASE_COOKIE = "/var/lib/pleroma/.cookie";
    # serviceConfig.ExecStartPre = let
    #   preScript = pkgs.writers.writeBashBin "pleromaStartPre" ''
    #     if [ ! -f /var/lib/pleroma/.cookie ]
    #     then
    #       echo "Creating cookie file"
    #       dd if=/dev/urandom bs=1 count=16 | hexdump -e '16/1 "%02x"' > /var/lib/pleroma/.cookie
    #     fi
    #     # ${config.services.pleroma.package}/bin/pleroma_ctl migrate
    #   '';
    # in "${preScript}/bin/pleromaStartPre";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      pleroma = {
        rule = "Host(`zone.dora.im`)";
        entryPoints = [ "https" ];
        service = "pleroma";
      };
    };
    services = {
      pleroma.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:4000"; } ];
      };
    };
  };
}
