{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.frp-panel.master;
  adminCfg = cfg.bootstrapAdmin;
in
{
  options.services.frp-panel.master = {
    enable = mkEnableOption "frp-panel master";
    package = mkOption {
      type = types.package;
      default = pkgs.frp-panel;
    };
    appId = mkOption {
      type = types.str;
      description = "Application ID for frp-panel";
    };
    globalSecret = mkOption {
      type = types.str;
      description = "Global Secret for frp-panel (App.GlobalSecret)";
    };
    masterSecret = mkOption {
      type = types.str;
      description = "Master Secret for frp-panel";
    };
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };
    port = mkOption {
      type = types.port;
      default = 18080;
    };
    grpcPort = mkOption {
      type = types.port;
      default = 15000;
    };
    extraConfig = mkOption {
      type = types.attrs;
      default = { };
    };
    bootstrapAdmin = {
      enable = mkEnableOption "bootstrap frp-panel admin user";
      username = mkOption {
        type = types.str;
        default = "i";
        description = "Username of the admin account to bootstrap.";
      };
      email = mkOption {
        type = types.str;
        default = "i@dora.im";
        description = "Email used when bootstrapping admin account.";
      };
      passwordSecret = mkOption {
        type = types.str;
        default = "password";
        description = "SOPS secret key containing bootstrap admin password.";
      };
      waitIntervalSeconds = mkOption {
        type = types.int;
        default = 2;
        description = "Interval in seconds between startup readiness checks.";
      };
      maxWaitAttempts = mkOption {
        type = types.int;
        default = 120;
        description = "Maximum readiness check attempts before failing bootstrap.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      sops.secrets."frp_panel/app_id" = { };
      sops.secrets."frp_panel/app_secret" = { };
      sops.secrets."frp_panel/master_secret" = { };
      sops.templates."frp-panel-master.env".content = ''
        APP_ID=${cfg.appId}
        APP_GLOBAL_SECRET=${cfg.globalSecret}
        MASTER_SECRET=${cfg.masterSecret}
        MASTER_API_PORT=${toString cfg.port}
        MASTER_RPC_PORT=${toString cfg.grpcPort}
        MASTER_RPC_HOST=${cfg.host}
        DB_TYPE=sqlite3
        DB_DSN=/var/lib/frp-panel/data.db?_pragma=journal_mode(WAL)
        GIN_MODE=release
      '';

      systemd.services.frp-panel-master = {
        description = "frp-panel master service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          StateDirectory = "frp-panel";
          ExecStart = "${cfg.package}/bin/frp-panel master";
          Restart = "always";
          EnvironmentFile = config.sops.templates."frp-panel-master.env".path;
        };
      };

      systemd.services.frp-panel-cleanup = {
        description = "Cleanup inactive ephemeral frp-panel nodes";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "frp-panel-cleanup" ''
            DB_PATH="/var/lib/frp-panel/data.db"
            if [ -f "$DB_PATH" ]; then
               # Delete clients where ephemeral=1 and last_seen is older than 7 days
               ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "DELETE FROM clients WHERE ephemeral = 1 AND (last_seen_at < datetime('now', '-7 days') OR (last_seen_at IS NULL AND created_at < datetime('now', '-1 day')));"
            fi
          '';
        };
      };

      systemd.timers.frp-panel-cleanup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

      networking.firewall.allowedTCPPorts = [
        cfg.port
        cfg.grpcPort
      ];
    }

    (mkIf adminCfg.enable (mkMerge [
      (setAttrByPath [ "sops" "secrets" adminCfg.passwordSecret ] {
        restartUnits = [ "frp-panel-bootstrap-admin.service" ];
      })

      {
        assertions = [
          {
            assertion = adminCfg.waitIntervalSeconds > 0;
            message = "services.frp-panel.master.bootstrapAdmin.waitIntervalSeconds must be > 0";
          }
          {
            assertion = adminCfg.maxWaitAttempts > 0;
            message = "services.frp-panel.master.bootstrapAdmin.maxWaitAttempts must be > 0";
          }
        ];

        systemd.services.frp-panel-bootstrap-admin = {
          description = "Bootstrap frp-panel admin user";
          wantedBy = [ "multi-user.target" ];
          requires = [ "frp-panel-master.service" ];
          after = [ "frp-panel-master.service" ];
          path = with pkgs; [
            coreutils
            curl
            python3
          ];
          serviceConfig = {
            Type = "oneshot";
            Environment = [
              "MASTER_URL=http://127.0.0.1:${toString cfg.port}"
              "ADMIN_USERNAME=${adminCfg.username}"
              "ADMIN_EMAIL=${adminCfg.email}"
              "ADMIN_PASSWORD_FILE=${config.sops.secrets.${adminCfg.passwordSecret}.path}"
              "WAIT_INTERVAL_SECONDS=${toString adminCfg.waitIntervalSeconds}"
              "MAX_WAIT_ATTEMPTS=${toString adminCfg.maxWaitAttempts}"
            ];
            ExecStart = pkgs.writeShellScript "frp-panel-bootstrap-admin" ''
                            set -euo pipefail

                            parse_status_code() {
                              local response="''${1:-}"
                              printf '%s' "$response" | ${pkgs.python3}/bin/python3 - <<'PY'
              import json
              import sys

              try:
                  data = json.load(sys.stdin)
                  print(((data.get("body") or {}).get("status") or {}).get("code", -1))
              except Exception:
                  print(-1)
              PY
                            }

                            parse_status_message() {
                              local response="''${1:-}"
                              printf '%s' "$response" | ${pkgs.python3}/bin/python3 - <<'PY'
              import json
              import sys

              try:
                  data = json.load(sys.stdin)
                  print(((data.get("body") or {}).get("status") or {}).get("message", ""))
              except Exception:
                  print("")
              PY
                            }

                            build_payload() {
                              local username="$1"
                              local password="$2"
                              local email="$3"
                              USERNAME="$username" PASSWORD="$password" EMAIL="$email" ${pkgs.python3}/bin/python3 - <<'PY'
              import json
              import os

              payload = {
                  "username": os.environ["USERNAME"],
                  "password": os.environ["PASSWORD"],
              }
              if os.environ.get("EMAIL"):
                  payload["email"] = os.environ["EMAIL"]
              print(json.dumps(payload, ensure_ascii=False))
              PY
                            }

                            api_post() {
                              local endpoint="$1"
                              local payload="$2"
                              ${pkgs.curl}/bin/curl \
                                --silent --show-error \
                                --request POST \
                                --header "Content-Type: application/json" \
                                --data "$payload" \
                                "$MASTER_URL$endpoint"
                            }

                            if [ ! -r "$ADMIN_PASSWORD_FILE" ]; then
                              echo "frp-panel bootstrap: password file is not readable: $ADMIN_PASSWORD_FILE" >&2
                              exit 1
                            fi

                            ADMIN_PASSWORD="$(tr -d '\r\n' < "$ADMIN_PASSWORD_FILE")"
                            if [ -z "$ADMIN_PASSWORD" ]; then
                              echo "frp-panel bootstrap: admin password is empty" >&2
                              exit 1
                            fi

                            ready_http_code=""
                            for attempt in $(seq 1 "$MAX_WAIT_ATTEMPTS"); do
                              ready_http_code="$(${pkgs.curl}/bin/curl \
                                --silent --show-error \
                                --output /dev/null \
                                --write-out "%{http_code}" \
                                --request POST \
                                --header "Content-Type: application/json" \
                                --data '{"username":"bootstrap-check","password":"bootstrap-check"}' \
                                "$MASTER_URL/api/v1/auth/login" || true)"
                              if [ "$ready_http_code" = "200" ]; then
                                break
                              fi
                              echo "Waiting for frp-panel to start... (attempt $attempt/$MAX_WAIT_ATTEMPTS, http=$ready_http_code)"
                              sleep "$WAIT_INTERVAL_SECONDS"
                            done

                            if [ "$ready_http_code" != "200" ]; then
                              echo "frp-panel bootstrap: API not ready after $MAX_WAIT_ATTEMPTS attempts" >&2
                              exit 1
                            fi

                            login_payload="$(build_payload "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "")"
                            login_response="$(api_post "/api/v1/auth/login" "$login_payload")"
                            login_status_code="$(parse_status_code "$login_response")"
                            if [ "$login_status_code" = "1" ]; then
                              echo "frp-panel bootstrap: admin user already available ($ADMIN_USERNAME)"
                              exit 0
                            fi

                            register_payload="$(build_payload "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$ADMIN_EMAIL")"
                            register_response="$(api_post "/api/v1/auth/register" "$register_payload")"
                            register_status_code="$(parse_status_code "$register_response")"
                            if [ "$register_status_code" = "1" ]; then
                              echo "frp-panel bootstrap: admin user created ($ADMIN_USERNAME)"
                              exit 0
                            fi

                            db_path="/var/lib/frp-panel/data.db"
                            if [ -f "$db_path" ]; then
                              user_count="$(DB_PATH="$db_path" ADMIN_USERNAME="$ADMIN_USERNAME" ${pkgs.python3}/bin/python3 - <<'PY'
              import os
              import sqlite3

              db_path = os.environ["DB_PATH"]
              username = os.environ["ADMIN_USERNAME"]

              try:
                  conn = sqlite3.connect(db_path)
                  cur = conn.cursor()
                  cur.execute("SELECT COUNT(*) FROM users WHERE user_name = ?", (username,))
                  row = cur.fetchone()
                  print(int(row[0]) if row and row[0] is not None else 0)
              except Exception:
                  print(0)
              PY
                              )"
                              if [ "$user_count" -ge 1 ]; then
                                echo "frp-panel bootstrap: user exists in DB, skip register ($ADMIN_USERNAME)"
                                exit 0
                              fi
                            fi

                            register_status_message="$(parse_status_message "$register_response")"
                            echo "frp-panel bootstrap failed: register status=$register_status_code message=$register_status_message" >&2
                            exit 1
            '';
          };
        };
      }
    ]))

    (mkIf (options ? services.traefik.proxies) {
      services.traefik.proxies = {
        frp-panel-master = {
          rule = "Host(`frp-master.${config.networking.domain}`)";
          target = "http://127.0.0.1:${toString cfg.port}";
        };
        frp-panel = {
          rule = "Host(`frp.${config.networking.domain}`)";
          target = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    })
  ]);
}
