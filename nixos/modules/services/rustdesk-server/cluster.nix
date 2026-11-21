{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.rustdesk-server;
  inherit (cfg) cluster;
  isSignal = cluster.role == "signal";
  mapped = cluster.relayPort != config.ports.rustdesk-relay;
  python = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
  forapiPackage = pkgs.callPackage ../../../../pkgs/rustdesk-server-forapi { };
  apiPackage = pkgs.callPackage ../../../../pkgs/rustdesk-api { };
  apiEnabled = isSignal && cluster.api.enable;
  databaseName = "rustdesk";
  databaseEnvironment = {
    PGHOST = "127.0.0.1";
    PGPORT = toString config.services.postgresql.settings.port;
    PGUSER = databaseName;
    PGDATABASE = databaseName;
  };
  apiCredentials = [
    "public-key:${config.sops.secrets."rustdesk/server_public_key".path}"
    "api-jwt:${config.sops.secrets."rustdesk/api_jwt_key".path}"
    "admin-password:${config.sops.secrets.password.path}"
  ];
  apiStart = pkgs.writeShellScript "rustdesk-api-start" ''
    set -euo pipefail
    install -d -m 0700 /var/lib/rustdesk-api/data
    install -d -m 0700 /var/lib/rustdesk-api/runtime
    ln -sfn ${apiPackage}/libexec/rustdesk-api/resources /var/lib/rustdesk-api/resources
    install -d -m 0700 /var/lib/rustdesk-api/conf
    ln -sfn ${apiPackage}/libexec/rustdesk-api/conf/admin /var/lib/rustdesk-api/conf/admin
    export RUSTDESK_API_LANG=zh-CN
    export RUSTDESK_API_APP_WEB_CLIENT=1
    export RUSTDESK_API_APP_REGISTER=${lib.boolToString cluster.api.register}
    export RUSTDESK_API_APP_REGISTER_STATUS=2
    export RUSTDESK_API_APP_TOKEN_EXPIRE=${lib.escapeShellArg cluster.api.tokenTtl}
    export RUSTDESK_API_GIN_API_ADDR=127.0.0.1:${toString cluster.api.port}
    export RUSTDESK_API_GIN_MODE=release
    export RUSTDESK_API_GIN_RESOURCES_PATH=${apiPackage}/libexec/rustdesk-api/resources
    export RUSTDESK_API_GORM_TYPE=postgresql
    export RUSTDESK_API_GORM_MAX_IDLE_CONNS=2
    export RUSTDESK_API_GORM_MAX_OPEN_CONNS=10
    export RUSTDESK_API_POSTGRESQL_HOST="$PGHOST"
    export RUSTDESK_API_POSTGRESQL_PORT="$PGPORT"
    export RUSTDESK_API_POSTGRESQL_USER="$PGUSER"
    export RUSTDESK_API_POSTGRESQL_DBNAME="$PGDATABASE"
    # The upstream DSN interpolates password= verbatim; quoted empty avoids
    # pgx treating the following dbname= field as the password.
    export RUSTDESK_API_POSTGRESQL_PASSWORD=${lib.escapeShellArg "''"}
    export RUSTDESK_API_POSTGRESQL_SSLMODE=disable
    export RUSTDESK_API_POSTGRESQL_TIME_ZONE=Asia/Shanghai
    export RUSTDESK_API_RUSTDESK_ID_SERVER=${cluster.api.domain}:${toString signal}
    export RUSTDESK_API_RUSTDESK_RELAY_SERVER=fra0.dora.im:${toString relay}
    export RUSTDESK_API_RUSTDESK_API_SERVER=https://${cluster.api.domain}
    export RUSTDESK_API_RUSTDESK_KEY_FILE=$CREDENTIALS_DIRECTORY/public-key
    export RUSTDESK_API_RUSTDESK_PERSONAL=1
    export RUSTDESK_API_JWT_KEY="$(cat "$CREDENTIALS_DIRECTORY/api-jwt")"
    exec ${apiPackage}/bin/rustdesk-api -c ${apiPackage}/libexec/rustdesk-api/conf/config.yaml
  '';
  signal = config.ports.rustdesk-signal;
  relay = config.ports.rustdesk-relay;
  restartUnits = [ "rustdesk-relay.service" ] ++ lib.optional isSignal "rustdesk-signal.service";
  credentials = [ "public-key:${config.sops.secrets."rustdesk/server_public_key".path}" ];
  signalCredentials =
    credentials
    ++ lib.optional isSignal "private-key:${config.sops.secrets."rustdesk/server_private_key".path}"
    ++
      lib.optional (isSignal && cluster.api.enable)
        "api-jwt:${config.sops.secrets."rustdesk/api_jwt_key".path}";
  exec =
    mode: binary: args:
    lib.escapeShellArgs (
      [
        "${python}/bin/python3"
        "${./runtime.py}"
        mode
        "${cfg.package}/bin/${binary}"
      ]
      ++ args
    );
  defaults = {
    after = [
      "sops-install-secrets.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "sops-install-secrets.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      NoNewPrivileges = true;
      LimitNOFILE = 65536;
    };
  };
in
{
  options.services.rustdesk-server.cluster = {
    enable = lib.mkEnableOption "the RustDesk OSS multi-relay deployment";
    role = lib.mkOption {
      type = lib.types.enum [
        "signal"
        "relay"
      ];
      default = "relay";
      description = "One central signal/ID database plus its relay, or a relay-only edge.";
    };
    relayHosts = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9.-]+:[0-9]+");
      default = [ ];
      description = "Default pool reachable from hbbs; OSS checks TCP liveness, then round-robins.";
    };
    relayPort = lib.mkOption {
      type = lib.types.port;
      default = relay;
      description = "Public native TCP relay port. A different port uses source-preserving nft redirect.";
    };
    bandwidth = {
      perSession = lib.mkOption {
        type = lib.types.ints.positive;
        default = 128;
      };
      total = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1024;
      };
    };
    api = {
      enable = lib.mkEnableOption "the RustDesk API/admin/Web Client control plane";
      domain = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9.-]+";
        default = "rustdesk.dora.im";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 21114;
      };
      tokenTtl = lib.mkOption {
        type = lib.types.str;
        default = "168h";
      };
      register = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };
  config = lib.mkIf cluster.enable {
    assertions = [
      {
        assertion = !isSignal || cluster.relayHosts != [ ];
        message = "RustDesk hbbs requires a nonempty relay pool.";
      }
      {
        assertion = config.networking.nftables.enable && (!mapped || !isSignal);
        message = "RustDesk cluster uses the existing nftables backend; mapped ports require relay-only mode.";
      }
      {
        assertion = !cluster.api.enable || isSignal;
        message = "The RustDesk API control plane can only run beside the signal server.";
      }
      {
        assertion = !apiEnabled || config.services.postgresql.enable;
        message = "RustDesk API requires the host's existing PostgreSQL service.";
      }
    ];
    services.rustdesk-server = {
      enable = true;
      package = lib.mkDefault forapiPackage;
      openFirewall = false;
      signal.enable = isSignal;
      relay.enable = true;
      # Nixpkgs joins this option with ':', whereas hbbs requires commas.
      signal.relayHosts = lib.mkForce [ (lib.concatStringsSep "," cluster.relayHosts) ];
    };
    services.postgresql = lib.mkIf apiEnabled {
      ensureDatabases = [ databaseName ];
      ensureUsers = [
        {
          name = databaseName;
          ensureDBOwnership = true;
        }
      ];
    };
    sops.secrets."rustdesk/server_private_key" = lib.mkIf isSignal {
      sopsFile = config.sops-file.get "common.yaml";
      restartUnits = [ "rustdesk-signal.service" ];
    };
    sops.secrets."rustdesk/api_jwt_key" = lib.mkIf (isSignal && cluster.api.enable) {
      sopsFile = config.sops-file.get "common.yaml";
      restartUnits = [
        "rustdesk-signal.service"
        "rustdesk-api.service"
      ];
    };
    sops.secrets.password = lib.mkIf apiEnabled {
      sopsFile = config.sops-file.get "common.yaml";
      restartUnits = [ "rustdesk-api.service" ];
    };
    sops.secrets."rustdesk/server_public_key" = {
      sopsFile = config.sops-file.get "common.yaml";
      inherit restartUnits;
    };
    networking.firewall = {
      # Input filtering runs after prerouting redirect and sees its target port.
      allowedTCPPorts = [
        relay
      ]
      ++ lib.optionals isSignal [
        (signal - 1)
        signal
      ];
      allowedUDPPorts = lib.optional isSignal signal;
    };
    networking.nftables.tables.rustdesk-ports = {
      family = "inet";
      content = ''
        ${lib.optionalString mapped ''
          chain relay_redirect {
            type nat hook prerouting priority dstnat; policy accept;
            fib daddr type local tcp dport ${toString cluster.relayPort} redirect to :${toString relay}
          }
        ''}
        chain native_only {
          type filter hook input priority -10; policy accept;
          iifname != "lo" tcp dport { ${
            lib.concatStringsSep ", " (map toString ([ (relay + 2) ] ++ lib.optional isSignal (signal + 2)))
          } } drop
          ${lib.optionalString mapped ''
            iifname != "lo" tcp dport ${toString relay} ct original proto-dst != ${toString cluster.relayPort} drop
          ''}
        }
      '';
    };
    systemd.services = {
      rustdesk-signal = lib.mkIf isSignal (
        lib.mkMerge [
          defaults
          {
            serviceConfig = {
              ExecStart = lib.mkForce (
                exec "signal" "hbbs" [
                  "--port"
                  (toString signal)
                  "--key"
                  "_"
                  "--relay-servers"
                  (lib.concatStringsSep "," cluster.relayHosts)
                ]
              );
              LoadCredential = signalCredentials;
            };
          }
        ]
      );
      rustdesk-relay = lib.mkMerge [
        defaults
        {
          environment = {
            # Upstream units are 1024*1024 bit/s, not decimal Mbit/s.
            SINGLE_BANDWIDTH = toString cluster.bandwidth.perSession;
            TOTAL_BANDWIDTH = toString cluster.bandwidth.total;
            # Avoid the stock 32-unit downgrade after a long viewing session.
            LIMIT_SPEED = toString cluster.bandwidth.perSession;
            DOWNGRADE_THRESHOLD = "1";
          };
          serviceConfig = {
            ExecStart = lib.mkForce (
              exec "relay" "hbbr" [
                "--port"
                (toString relay)
              ]
            );
            LoadCredential = credentials;
          };
        }
      ];
      rustdesk-api = lib.mkIf apiEnabled {
        wantedBy = [ "rustdesk.target" ];
        path = [ config.services.postgresql.package ];
        after = [
          "sops-install-secrets.service"
          "rustdesk-signal.service"
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "sops-install-secrets.service"
          "rustdesk-signal.service"
          "postgresql.service"
          "postgresql-setup.service"
        ];
        environment = databaseEnvironment;
        serviceConfig = {
          ExecStart = apiStart;
          ExecStartPre = "${python}/bin/python3 ${./runtime.py} admin";
          LoadCredential = apiCredentials;
          StateDirectory = "rustdesk-api";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/rustdesk-api";
          DynamicUser = true;
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          LimitNOFILE = 1000000;
        };
      };
    };
    services.traefik.proxies.rustdesk-api = lib.mkIf (isSignal && cluster.api.enable) {
      rule = "Host(`${cluster.api.domain}`)";
      target = "http://127.0.0.1:${toString cluster.api.port}";
      priority = 20;
    };
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "rustdesk-server-key" ''
        exec ${python}/bin/python3 ${./runtime.py} public ${
          lib.escapeShellArg config.sops.secrets."rustdesk/server_public_key".path
        }
      '')
    ];
    # The base persistence profile already persists all of /var/lib.
  };
}
