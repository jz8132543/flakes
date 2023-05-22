{ config
, pkgs
, self
, lib
, ...
}: {
  # matrix-synapse
  sops.secrets."matrix/mail" = { };
  sops.secrets."matrix/signing-key" = { };
  sops.secrets."b2/keyID" = { };
  sops.secrets."b2/applicationKey" = { };
  services.matrix-synapse = {
    enable = true;
    withJemalloc = true;
    plugins = [
      config.nur.repos.linyinfeng.synapse-s3-storage-provider
    ];
    settings = {
      server_name = "dora.im";
      public_baseurl = "https://matrix.dora.im";
      admin_contact = "mailto:i@dora.im";
      signing_key_path = config.sops.secrets."matrix/signing-key".path;

      database = {
        name = "psycopg2";
        args = {
          # local database
          database = "matrix-synapse";
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
          bind_addresses = [ "127.0.0.1" ];
          port = config.ports.matrix;
          tls = false;
          type = "http";
          x_forwarded = true;
          resources = [
            {
              compress = true;
              names = [ "client" "federation" ];
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
        smtp_host = "smtp.dora.im";
        smtp_user = "matrix@dora.im";
        notif_from = "matrix@dora.im";
        force_tls = true;
        smtp_pass = config.sops.placeholder."matrix/mail";
      };
      media_storage_providers = [
        # as backup of all local media
        {
          module = "s3_storage_provider.S3StorageProviderBackend";
          store_local = true;
          store_remote = false;
          store_synchronous = true;
          config = {
            bucket = config.lib.self.data.matrix.media.name;
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

  # systemd.services.matrix-synapse = {
  #   # copy singing key to signing key path
  #   serviceConfig.ExecStartPre = lib.mkBefore [
  #     ("+"
  #       + (pkgs.writeShellScript "matrix-synapse-fix-permissions" ''
  #         cp "${config.sops.secrets."synapse/signing-key".path}" "${config.services.matrix-synapse.settings.signing_key_path}"
  #         chown matrix-synapse:matrix-synapse "${config.services.matrix-synapse.settings.signing_key_path}"
  #       ''))
  #   ];
}
