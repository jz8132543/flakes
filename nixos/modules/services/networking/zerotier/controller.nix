{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    types
    ;
  cfg = config.services.zerotierMesh.controller;
  ztPackage = config.services.zerotierone.package;
  enrollmentApiScript = pkgs.writeText "zerotier-enrollment-api.py" ''
    import http.server
    import json
    import os

    TOKEN_FILE = os.environ["TOKEN_FILE"]
    NETWORK_ID_FILE = os.environ["NETWORK_ID_FILE"]
    CONTROLLER_ID_FILE = os.environ["CONTROLLER_ID_FILE"]
    NETWORK_NAME = os.environ["NETWORK_NAME"]
    LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
    LISTEN_PORT = int(os.environ["LISTEN_PORT"])

    def read_trimmed(path):
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "ZeroTierEnroll/1.0"

        def _send(self, status, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            return

        def do_GET(self):
            if self.path == "/healthz":
                self._send(200, {"ok": True})
                return

            if self.path != "/v1/network":
                self._send(404, {"error": "not_found"})
                return

            auth = self.headers.get("Authorization", "")
            expected = "Bearer " + read_trimmed(TOKEN_FILE)
            if auth != expected:
                self._send(403, {"error": "forbidden"})
                return

            self._send(
                200,
                {
                    "networkId": read_trimmed(NETWORK_ID_FILE),
                    "controllerId": read_trimmed(CONTROLLER_ID_FILE),
                    "networkName": NETWORK_NAME,
                },
            )

    http.server.ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
  '';
  controllerLocalConf = {
    settings = {
      allowSecondaryPort = false;
      inherit (cfg) allowTcpFallbackRelay;
      concurrency = 1;
      cpuPinningEnabled = false;
      enableWebServer = false;
      forceTcpRelay = false;
      lowBandwidthMode = false;
      multicoreEnabled = false;
      portMappingEnabled = false;
      primaryPort = cfg.port;
      tertiaryPort = 0;
    };
  };
in
{
  options.services.zerotierMesh.controller = {
    enable = mkEnableOption "self-hosted ZeroTier controller with auto-enrollment";
    publicHost = mkOption {
      type = types.str;
      default = "zt.${config.networking.domain}";
      description = "Public host name used for the enrollment API.";
    };
    networkName = mkOption {
      type = types.str;
      default = "dora-mesh";
    };
    networkSuffix = mkOption {
      type = types.str;
      default = "000001";
      description = "Last 6 hex digits appended to the controller node ID.";
    };
    port = mkOption {
      type = types.port;
      default = 9993;
    };
    enrollmentPort = mkOption {
      type = types.port;
      default = 31893;
    };
    mtu = mkOption {
      type = types.int;
      default = 2800;
    };
    ipv4Cidr = mkOption {
      type = types.str;
      default = "172.30.0.0/16";
    };
    controllerIpv4 = mkOption {
      type = types.str;
      default = "172.30.0.1";
    };
    ipv4PoolStart = mkOption {
      type = types.str;
      default = "172.30.0.10";
    };
    ipv4PoolEnd = mkOption {
      type = types.str;
      default = "172.30.255.250";
    };
    allowTcpFallbackRelay = mkOption {
      type = types.bool;
      default = false;
    };
    exposeEnrollmentApi = mkOption {
      type = types.bool;
      default = true;
    };
    exitNode = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      externalInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      ipv6 = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = builtins.match "^[0-9a-fA-F]{6}$" cfg.networkSuffix != null;
          message = "services.zerotierMesh.controller.networkSuffix must be exactly 6 hex digits";
        }
        {
          assertion = (!cfg.exitNode.enable) || cfg.exitNode.externalInterface != null;
          message = "services.zerotierMesh.controller.exitNode.externalInterface is required when exitNode.enable = true";
        }
      ];

      sops.secrets."fw_proxy_external_controller_secret" = {
        restartUnits = [
          "zerotier-bootstrap-network.service"
          "zerotier-enrollment-api.service"
        ];
      };

      services.zerotierone = {
        enable = true;
        inherit (cfg) port;
        localConf = controllerLocalConf;
      };

      networking.firewall.allowedTCPPorts = optional cfg.allowTcpFallbackRelay cfg.port;

      systemd.services.zerotier-bootstrap-network = {
        description = "Bootstrap ZeroTier controller network";
        after = [ "zerotierone.service" ];
        requires = [ "zerotierone.service" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          coreutils
          gnugrep
          jq
        ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          set -euo pipefail

          home=/var/lib/zerotier-one
          token_file=${config.sops.secrets."fw_proxy_external_controller_secret".path}

          zerotier_cli() {
            exec -a zerotier-cli ${ztPackage}/bin/zerotier-one -D"$home" "$@"
          }

          for _ in $(seq 1 60); do
            if [ -s "$home/identity.public" ] && [ -s "$home/authtoken.secret" ]; then
              break
            fi
            sleep 1
          done

          if [ ! -s "$home/identity.public" ]; then
            echo "ZeroTier controller identity is not ready" >&2
            exit 1
          fi

          controller_id=$(cut -d: -f1 < "$home/identity.public")
          network_id="''${controller_id}${cfg.networkSuffix}"
          enrollment_token=$(tr -d '\r\n' < "$token_file")

          mkdir -p "$home/controller.d/$network_id/member" "$home/networks.d"

          jq -n \
            --arg id "$network_id" \
            --arg name "${cfg.networkName}" \
            --arg ipv4_cidr "${cfg.ipv4Cidr}" \
            --arg pool_start "${cfg.ipv4PoolStart}" \
            --arg pool_end "${cfg.ipv4PoolEnd}" \
            --arg token "$enrollment_token" \
            --argjson mtu ${toString cfg.mtu} \
            --argjson private false \
            --argjson enable_broadcast true \
            --argjson multicast_limit 32 \
            --argjson default_route ${if cfg.exitNode.enable then "true" else "false"} \
            --arg default_via "${cfg.controllerIpv4}" \
            '
            {
              id: $id,
              objtype: "network",
              name: $name,
              private: $private,
              enableBroadcast: $enable_broadcast,
              multicastLimit: $multicast_limit,
              mtu: $mtu,
              v4AssignMode: { zt: false },
              v6AssignMode: { rfc4193: true, zt: true, "6plane": true },
              authTokens: { ($token): 0 },
              capabilities: [],
              tags: [],
              ipAssignmentPools: [
                {
                  ipRangeStart: $pool_start,
                  ipRangeEnd: $pool_end
                }
              ],
              routes:
                ([{ target: $ipv4_cidr }])
                + (if $default_route then [{ target: "0.0.0.0/0", via: $default_via }] else [] end),
              rules: [
                {
                  not: false,
                  or: false,
                  type: "ACTION_ACCEPT"
                }
              ]
            }' > "$home/controller.d/$network_id.json.tmp"
          install -m 0600 "$home/controller.d/$network_id.json.tmp" "$home/controller.d/$network_id.json"
          rm -f "$home/controller.d/$network_id.json.tmp"

          jq -n \
            --arg id "$controller_id" \
            --arg nwid "$network_id" \
            --arg ip "${cfg.controllerIpv4}" \
            '
            {
              id: $id,
              nwid: $nwid,
              authorized: true,
              noAutoAssignIps: false,
              ipAssignments: [$ip],
              tags: [],
              capabilities: [],
              activeBridge: false,
              ssoExempt: false,
              objtype: "member"
            }' > "$home/controller.d/$network_id/member/$controller_id.json.tmp"
          install -m 0600 "$home/controller.d/$network_id/member/$controller_id.json.tmp" "$home/controller.d/$network_id/member/$controller_id.json"
          rm -f "$home/controller.d/$network_id/member/$controller_id.json.tmp"

          printf '%s\n' "$network_id" > "$home/network-id"
          printf '%s\n' "$controller_id" > "$home/controller-id"
          touch "$home/networks.d/$network_id.conf"

          if ! zerotier_cli -j listnetworks | jq -e --arg nwid "$network_id" '.[] | select(.nwid == $nwid)' >/dev/null; then
            zerotier_cli join "$network_id"
          fi
        '';
      };

      systemd.services.zerotier-enrollment-api = mkIf cfg.exposeEnrollmentApi {
        description = "ZeroTier enrollment API";
        after = [
          "network-online.target"
          "zerotier-bootstrap-network.service"
        ];
        requires = [ "zerotier-bootstrap-network.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${enrollmentApiScript}";
          Environment = [
            "TOKEN_FILE=${config.sops.secrets."fw_proxy_external_controller_secret".path}"
            "NETWORK_ID_FILE=/var/lib/zerotier-one/network-id"
            "CONTROLLER_ID_FILE=/var/lib/zerotier-one/controller-id"
            "NETWORK_NAME=${cfg.networkName}"
            "LISTEN_HOST=127.0.0.1"
            "LISTEN_PORT=${toString cfg.enrollmentPort}"
          ];
          Restart = "always";
          RestartSec = "2s";
        };
      };

      services.traefik.proxies.zerotier-enrollment = mkIf cfg.exposeEnrollmentApi {
        rule = "Host(`${cfg.publicHost}`)";
        target = "http://127.0.0.1:${toString cfg.enrollmentPort}";
      };
    }

    (mkIf cfg.exitNode.enable {
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
      }
      // lib.optionalAttrs cfg.exitNode.ipv6 {
        "net.ipv6.conf.all.forwarding" = 1;
      };

      networking.nftables = {
        enable = true;
        tables.zerotier-exit = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "${cfg.exitNode.externalInterface}" ip saddr ${cfg.ipv4Cidr} masquerade
            }
          '';
        };
      };
    })
  ]);
}
