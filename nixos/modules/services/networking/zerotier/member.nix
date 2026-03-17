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
    mkOption
    optional
    types
    ;
  cfg = config.services.zerotierMesh.member;
  ztPackage = config.services.zerotierone.package;
  memberLocalConf = {
    settings = {
      allowSecondaryPort = false;
      inherit (cfg) allowTcpFallbackRelay;
      concurrency = 1;
      cpuPinningEnabled = false;
      enableWebServer = false;
      forceTcpRelay = false;
      lowBandwidthMode = cfg.lowResource;
      multicoreEnabled = false;
      portMappingEnabled = !cfg.lowResource;
      primaryPort = cfg.port;
      tertiaryPort = 0;
    };
  };
in
{
  options.services.zerotierMesh.member = {
    enable = mkEnableOption "auto-enrolled ZeroTier member";
    enrollmentUrl = mkOption {
      type = types.str;
      default = "https://zt.${config.networking.domain}/v1";
    };
    port = mkOption {
      type = types.port;
      default = 9993;
    };
    allowTcpFallbackRelay = mkOption {
      type = types.bool;
      default = true;
    };
    lowResource = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    sops.secrets."fw_proxy_external_controller_secret" = {
      restartUnits = [ "zerotier-auto-join.service" ];
    };

    services.zerotierone = {
      enable = true;
      inherit (cfg) port;
      localConf = memberLocalConf;
    };

    networking.firewall.allowedTCPPorts = optional cfg.allowTcpFallbackRelay cfg.port;

    systemd.services.zerotier-auto-join = {
      description = "Auto-join the managed ZeroTier network";
      after = [
        "network-online.target"
        "zerotierone.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "zerotierone.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        coreutils
        curl
        jq
      ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "10s";
      };
      script = ''
        set -euo pipefail

        home=/var/lib/zerotier-one
        token_file=${config.sops.secrets."fw_proxy_external_controller_secret".path}

        zerotier_cli() {
          exec -a zerotier-cli ${ztPackage}/bin/zerotier-one -D"$home" "$@"
        }

        for _ in $(seq 1 60); do
          if [ -s "$home/authtoken.secret" ]; then
            break
          fi
          sleep 1
        done

        enrollment_token=$(tr -d '\r\n' < "$token_file")
        network_json=$(curl --fail --silent --show-error \
          --header "Authorization: Bearer $enrollment_token" \
          "${cfg.enrollmentUrl}/network")
        network_id=$(printf '%s' "$network_json" | jq -r '.networkId')

        if [ -z "$network_id" ] || [ "$network_id" = "null" ]; then
          echo "ZeroTier enrollment API did not return a network ID" >&2
          exit 1
        fi

        if ! zerotier_cli -j listnetworks | jq -e --arg nwid "$network_id" '.[] | select(.nwid == $nwid)' >/dev/null; then
          zerotier_cli join "$network_id"
        fi

        printf '%s\n' "$network_id" > "$home/managed-network-id"
      '';
    };
  };
}
