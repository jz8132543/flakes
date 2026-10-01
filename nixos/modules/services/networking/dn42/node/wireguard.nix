{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    ;

  cfg = config.services.dn42.node;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.wireguard-tools ];

    assertions = [
      {
        assertion = cfg.gatewayPublicKey != null;
        message = "services.dn42.node.gatewayPublicKey must be set (or configured in lib/data/data.json under hosts.nue0.dn42_public_key).";
      }
    ];

    # ── 1. 自动生成节点本地 WireGuard 密钥（开箱即用） ────────────────
    systemd.services.dn42-node-wireguard-keygen = {
      description = "Generate WireGuard keys for DN42 node if missing";
      wantedBy = [ "multi-user.target" ];
      before = [ "network-pre.target" ];
      path = with pkgs; [
        wireguard-tools
        coreutils
      ];
      script = ''
        mkdir -p /var/lib/wireguard
        chmod 700 /var/lib/wireguard
        if [ ! -f "${cfg.privateKeyFile}" ]; then
          echo "Generating DN42 node WireGuard key..."
          wg genkey | (umask 077 && cat > "${cfg.privateKeyFile}")
          wg pubkey < "${cfg.privateKeyFile}" > "/var/lib/wireguard/dn42.pub"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── 2. WireGuard 客户端网络接口配置 ────────────────────────────────
    networking.wireguard.interfaces.dn42-gw = {
      ips = [
        cfg.nodeIpv4
        cfg.nodeIpv6
      ];
      inherit (cfg) privateKeyFile;
      peers = [
        {
          publicKey = cfg.gatewayPublicKey;
          endpoint = cfg.gatewayEndpoint;
          # 仅路由 DN42 私有 IPv4 和 IPv6 网段，完全不触碰公网默认路由与 Tailscale
          allowedIPs = [
            "172.20.0.0/14"
            "172.31.0.0/16"
            "10.0.0.0/8"
            "fd00::/8"
          ]
          ++ cfg.extraAllowedIPs;
          # 25 秒保活心跳，保证在 NAT/笔记本休眠唤醒后依然双向连通
          persistentKeepalive = 25;
        }
      ];
    };

    # 确保 WireGuard 在密钥准备完毕后启动
    systemd.services.wireguard-dn42-gw = {
      after = [ "dn42-node-wireguard-keygen.service" ];
      wants = [ "dn42-node-wireguard-keygen.service" ];
    };
  };
}
