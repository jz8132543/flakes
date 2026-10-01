{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mapAttrsToList
    mapAttrs'
    nameValuePair
    optional
    ;

  cfg = config.services.dn42.router;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.wireguard-tools ];

    # ── 1. 自动生成 WireGuard 密钥（开箱即用，避免初次部署因缺少密钥报错） ──
    systemd.services.dn42-router-wireguard-keygen = {
      description = "Generate WireGuard keys for DN42 router if missing";
      wantedBy = [ "multi-user.target" ];
      before = [ "network-pre.target" ];
      path = with pkgs; [
        wireguard-tools
        coreutils
      ];
      script = ''
        mkdir -p /var/lib/wireguard
        chmod 700 /var/lib/wireguard

        # 内部汇聚网关密钥
        if [ ! -f "${cfg.internalPrivateKeyFile}" ]; then
          echo "Generating DN42 internal WireGuard key..."
          wg genkey | (umask 077 && cat > "${cfg.internalPrivateKeyFile}")
          wg pubkey < "${cfg.internalPrivateKeyFile}" > "/var/lib/wireguard/dn42_internal.pub"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── 2. WireGuard 接口创建 ──────────────────────────────────────────
    networking.wireguard.interfaces =
      # 外部 eBGP Peers 专属 WireGuard 虚拟网卡 (dn42-peer-<name>)
      (mapAttrs' (
        name: p:
        nameValuePair "dn42-peer-${name}" {
          ips = [ p.ourLinkLocalIpv6 ] ++ optional (p.ourIpv4 != null) p.ourIpv4;
          inherit (p) listenPort;
          inherit (p) privateKeyFile;
          peers = [
            (
              {
                inherit (p) publicKey;
                allowedIPs = [
                  "0.0.0.0/0"
                  "::/0"
                ]; # BIRD 负责动态路由分发
                persistentKeepalive = 25;
              }
              // (lib.optionalAttrs (p.endpoint != null) {
                inherit (p) endpoint;
              })
            )
          ];
        }
      ) cfg.peers)
      //
      # 内部节点及笔记本接入 WireGuard 汇聚网卡 (dn42-internal)
      {
        dn42-internal = {
          ips = [
            cfg.nodeIpv4
            cfg.nodeIpv6
          ];
          listenPort = cfg.internalListenPort;
          privateKeyFile = cfg.internalPrivateKeyFile;
          peers = mapAttrsToList (_nodeName: node: {
            inherit (node) publicKey;
            allowedIPs = node.allowedIps;
            persistentKeepalive = 25;
          }) cfg.internalNodes;
        };
      };

    # 确保 WireGuard 接口在密钥准备完毕后启动
    systemd.services.wireguard-dn42-internal = {
      after = [ "dn42-router-wireguard-keygen.service" ];
      wants = [ "dn42-router-wireguard-keygen.service" ];
    };

    # ── 3. 防火墙自动放行外部与内部 WireGuard 端口 ─────────────────────
    networking.firewall.allowedUDPPorts = [
      cfg.internalListenPort
    ]
    ++ (mapAttrsToList (_: p: p.listenPort) cfg.peers);
  };
}
