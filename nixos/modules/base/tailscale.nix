{
  lib,
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  interfaceName = "tailscale0";
in
{
  imports = [ nixosModules.services.restic ];
  config = lib.mkMerge [
    {
      services.tailscale = {
        enable = lib.mkDefault true;
        openFirewall = true;
        useRoutingFeatures = "both";
        # 将 DNS 归属保留给本地 dnsmasq 前端，避免 Tailscale
        # 把 100.100.100.100 提升为全局解析器。
        extraSetFlags = [
          "--netfilter-mode=nodivert"
          "--accept-dns=false"
        ];
        extraDaemonFlags = [ "--no-logs-no-support" ];
      };
      networking = {
        networkmanager.unmanaged = [ interfaceName ];
        firewall = {
          # checkReversePath = false;
          trustedInterfaces = [ "tailscale0" ];
          allowedUDPPorts = [
            config.services.tailscale.port
            3478
          ];
        };
      };

      sops.secrets.tailscale_preauth_key = { };

      systemd.services.tailscale-setup = {
        enable = lib.mkDefault true;
        description = "Tailscale automatic login";
        after = [
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.services.tailscale.package
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
        ];
        script = ''
          login_server=https://ts.${config.networking.domain}

          # 等待 tailscaled 就绪
          sleep 2

          # 如果配置的登录服务器未提供 Tailscale control API，就尽快失败。
          if ! curl -fsSI --max-time 10 "$login_server/key" >/dev/null; then
            echo "Login server $login_server is not serving the Tailscale control API"
            exit 1
          fi

          # 检查是否已经完成认证
          status=$(tailscale status --json | jq -r .BackendState)
          if [ "$status" = "Running" ]; then
            echo "Tailscale is already running and authenticated."
            exit 0
          fi

          echo "Tailscale not authenticated (state: $status), logging in..."
          timeout 2m tailscale up \
            --reset \
            --login-server "$login_server" \
            --auth-key "file:${config.sops.secrets.tailscale_preauth_key.path}" \
            ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags}
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10";
          TimeoutStartSec = "3m";
        };
      };

      services.networkd-dispatcher = {
        enable = true;
        rules = {
          "tailscale" = {
            onState = [ "routable" ];
            script = ''
              #!${pkgs.runtimeShell}
              netdev=$(${pkgs.iproute2}/bin/ip route show 0/0 | ${pkgs.coreutils}/bin/cut -f5 -d' ' || echo eth0)
              ${pkgs.ethtool}/bin/ethtool -K "$netdev" rx-udp-gro-forwarding on rx-gro-list off || true
            '';
          };
        };
      };

      systemd.services.tailscaled = {
        before = [ "network.target" ];
        serviceConfig = {
          Restart = "always";
          TimeoutStopSec = "5s";
        };
      };

      services.restic.backups.borgbase.paths = [
        "/var/lib/tailscale/tailscaled.state"
      ];
    }
  ];
}
