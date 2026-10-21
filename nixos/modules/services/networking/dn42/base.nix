{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  cfg = config.services.dn42;
  hostName = config.networking.hostName or "unknown";

  selfData = config.lib.self.data or (lib.importJSON ../../../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };

  thisHostData = selfData.hosts.${hostName} or { };
  thisHostMesh = dn42Data.mesh.${hostName} or { };

  hostIndex =
    if thisHostData ? host_indices && thisHostData.host_indices != [ ] then
      lib.head thisHostData.host_indices
    else
      thisHostMesh.id or (99);

  nodeIpv4Raw =
    if thisHostData ? dn42_addresses_v4 && thisHostData.dn42_addresses_v4 != [ ] then
      lib.head thisHostData.dn42_addresses_v4
    else
      thisHostMesh.dn42_ip4 or "172.20.232.${toString hostIndex}";

  nodeIpv6Raw =
    if thisHostData ? dn42_addresses_v6 && thisHostData.dn42_addresses_v6 != [ ] then
      lib.head thisHostData.dn42_addresses_v6
    else
      thisHostMesh.dn42_ip6 or "fd53:90fd:4bb6:${lib.toHexString hostIndex}::1";

  # Build /etc/hosts mapping from all hosts in data.json: <host>.<domain> -> IP
  dn42Domain = cfg.domain or (dn42Data.domain or "dn42");
  dn42HostList = lib.flatten (
    lib.mapAttrsToList (
      name: hData:
      let
        v4s = hData.dn42_addresses_v4 or [ ];
        v6s = hData.dn42_addresses_v6 or [ ];
      in
      lib.lists.map (ip: {
        hostName = "${name}.${dn42Domain}";
        inherit ip;
      }) (v4s ++ v6s)
    ) (selfData.hosts or { })
  );

  peerAliases = dn42Data.peerAliases or { };
  myAssignedPeers = lib.filterAttrs (_alias: targetHost: targetHost == hostName) peerAliases;
  myPeerAlias = if myAssignedPeers != { } then lib.head (lib.attrNames myAssignedPeers) else null;

  # Extract a trailing :port from "host:port" / "[v6]:port" strings (null when absent).
  # Kept local to base.nix so the shared cluster port set has no cross-module dependency.
  endpointPort =
    str:
    if str == null || !lib.isString str then
      null
    else if lib.hasInfix "]:" str then
      let
        parts = lib.splitString "]:" str;
        p = if lib.length parts >= 2 then lib.toInt (lib.last parts) else null;
      in
      if p != null && p > 0 && p < 65536 then p else null
    else if !lib.hasInfix "[" str && (lib.length (lib.splitString ":" str)) == 2 then
      let
        p = lib.toInt (lib.last (lib.splitString ":" str));
      in
      if p > 0 && p < 65536 then p else null
    else
      null;

  # All IKE / NAT-T ports used anywhere in the cluster: local ports, every peer's
  # declared ports and every published endpoint port (IPv4/IPv6, single or array).
  # Consumers: raw notrack, firewall holes, FakeHTTP bypass and ip-rule exemptions.
  clusterTunnelPorts = lib.unique (
    [
      500
      4500
      cfg.ikePort
      cfg.natTPort
    ]
    ++ lib.concatMap (node: [
      (node.ike_port or (node.ikePort or 500))
      (node.nat_t_port or (node.natTPort or 4500))
    ]) (lib.attrValues (dn42Data.mesh or { }))
    ++ lib.concatMap (
      node:
      let
        rawEp = node.endpoints or { };
        rawList =
          if lib.isList rawEp then
            (map (ep: if lib.isAttrs ep then (ep.port or null) else ep) rawEp)
          else if lib.isAttrs rawEp then
            lib.attrValues rawEp
          else
            [ ];
        rawEpSingle =
          if (node.endpoint or null) != null && lib.isString node.endpoint then [ node.endpoint ] else [ ];
        ports = map (v: if lib.isString v then endpointPort v else v) (rawList ++ rawEpSingle);
      in
      lib.filter (p: p != null && p != (node.listenPort or 51821) && p != 51820) ports
    ) (lib.attrValues (dn42Data.mesh or { }))
  );

  # nftables set literal for all cluster tunnel ports
  portsCsv = lib.concatStringsSep ", " (map toString clusterTunnelPorts);
in
{
  options.services.dn42 = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DN42 base networking infrastructure (dummy loopback, /etc/hosts, sysctl forwarding, keygen)";
    };

    role = mkOption {
      type = types.enum [
        "border"
        "internal"
      ];
      default = thisHostMesh.role or "internal";
      description = "Node role in DN42 topology ('border' or 'internal')";
    };

    domain = mkOption {
      type = types.str;
      default = dn42Data.domain or "dora.dn42";
      description = "DN42 network domain / TLD suffix (default: dora.dn42)";
    };

    populateHosts = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to inject all DN42 host records into /etc/hosts (disabled by default in favor of authoritative DNS).";
    };

    asn = mkOption {
      type = types.int;
      default = dn42Data.asn or 4242420115;
      description = "Our DN42 Autonomous System Number";
    };

    ipv4 = mkOption {
      type = types.str;
      default = dn42Data.ipv4 or "172.20.232.0/26";
      description = "Our allocated DN42 IPv4 CIDR block";
    };

    ipv6 = mkOption {
      type = types.str;
      default = dn42Data.ipv6 or "fd53:90fd:4bb6::/48";
      description = "Our allocated DN42 IPv6 CIDR block";
    };

    routerId = mkOption {
      type = types.str;
      default = nodeIpv4Raw;
      description = "BGP router ID (IPv4 address, derived from data.json)";
    };

    nodeIpv4 = mkOption {
      type = types.str;
      default = "${nodeIpv4Raw}/32";
      description = "Loopback IPv4 with mask (/32)";
    };

    nodeIpv6 = mkOption {
      type = types.str;
      default = "${nodeIpv6Raw}/128";
      description = "Loopback IPv6 with mask (/128)";
    };

    hostIndex = mkOption {
      type = types.int;
      default = hostIndex;
      description = "Host index used for generating link-local addresses (fe80::<hostIndex>/64)";
    };

    linkLocalIpv6 = mkOption {
      type = types.str;
      default = "fe80::${toString cfg.hostIndex}/64";
      description = "Link-local IPv6 address with mask for point-to-point tunnels";
    };

    peerAlias = mkOption {
      type = types.nullOr types.str;
      default = myPeerAlias;
      description = "Public peering alias assigned to this host (e.g. 'peer1', 'peer2', 'peer3', or null)";
    };

    useSopsSecret = mkOption {
      type = types.bool;
      default = cfg.peerAlias != null && config ? sops-file;
      description = "Automatically fetch WireGuard private key from sops encrypted peer secret";
    };

    privateKeyFile = mkOption {
      type = types.str;
      default =
        if cfg.useSopsSecret && cfg.peerAlias != null && config ? sops-file then
          config.sops.secrets."dn42/wireguard_private_key".path
        else
          "/var/lib/wireguard/dn42.key";
      description = "Path to local WireGuard private key file (supports /run/secrets/...)";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default =
        if
          cfg.peerAlias != null && dn42Data ? peerPublicKeys && dn42Data.peerPublicKeys ? ${cfg.peerAlias}
        then
          dn42Data.peerPublicKeys.${cfg.peerAlias}
        else
          thisHostData.dn42_public_key or null;
      description = "WireGuard public key of this host (read from peerPublicKeys or data.json)";
    };

    extraKeyFiles = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Additional WireGuard private key files to automatically generate if under /var/lib/wireguard/";
    };

    ikePort = mkOption {
      type = types.port;
      default = 500;
      description = "strongSwan charon.port (IKE 端口，必须与 natTPort 不同以免 Socket 冲突)";
    };

    natTPort = mkOption {
      type = types.port;
      default = 4500;
      description = "strongSwan charon.port_nat_t (实际承载 ESP-in-UDP 与 Mimic Fake-TCP 的监听端口)";
    };

    allClusterTunnelPorts = mkOption {
      type = types.listOf types.port;
      internal = true;
      readOnly = true;
      default = clusterTunnelPorts;
      description = "All IKE / NAT-T ports used across the DN42 mesh cluster (local ports, peer ports and every published endpoint port). Consumed by raw notrack, firewall, FakeHTTP bypass and ip-rule exemptions.";
    };

    firewall = {
      trustMeshTraffic = mkOption {
        type = types.bool;
        default = true;
        description = "Trust all inbound traffic arriving on DN42 interfaces (dn42 / dn42x-*) from DN42 address ranges (172.20.0.0/14, 172.31.0.0/16, 10.0.0.0/8, fd00::/8). Required for mesh-internal services such as the .dn42 SOCKS5 proxies; public interfaces remain fully filtered.";
      };
    };

    sdwan = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "启用多主控动态 XFRM SD-WAN 模式";
      };

      isController = mkOption {
        type = types.bool;
        default = thisHostMesh.is_controller or false;
        description = "是否作为 SD-WAN 注册中心主控节点 (由 Terraform dn42_nodes / dn42_overrides 统一定义)";
      };

      controllerPort = mkOption {
        type = types.port;
        default = 54500;
        description = "SD-WAN 控制端轻量级 HTTP JSON 同步端口";
      };
    };
  };

  config = mkIf cfg.enable {
    # ── 0. Peer 专属 WireGuard 密钥（由 sops-nix 解密） ───────────────
    sops.secrets = lib.mkIf (cfg.useSopsSecret && cfg.peerAlias != null && config ? sops-file) {
      "dn42/wireguard_private_key" = {
        sopsFile = config.sops-file.get "dn42/${cfg.peerAlias}.yaml";
        key = "wireguard_private_key";
        mode = "0400";
      };
    };
    # ── 1. 基础系统工具 ─────────────────────────────────────────────
    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.bird2
    ];

    # ── 2. 内核转发与宽松反向路径过滤（sysctl） ─────────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
      "net.ipv6.conf.default.forwarding" = lib.mkDefault 1;
      "net.ipv4.conf.all.rp_filter" = lib.mkDefault 0;
      "net.ipv4.conf.default.rp_filter" = lib.mkDefault 0;
      # 开启 IPv6 转发时，Linux 内核默认会将 accept_ra 设为 0，导致外网物理网卡丢失 IPv6 默认网关。显式设为 2 确保继续接收路由通告
      "net.ipv6.conf.all.accept_ra" = lib.mkDefault 2;
      "net.ipv6.conf.default.accept_ra" = lib.mkDefault 2;
    };

    networking.firewall.checkReversePath = lib.mkDefault "loose";

    # Disable reverse-path filtering on dynamic tunnel devices for asymmetric paths.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="net", KERNEL=="dn42*", RUN+="${pkgs.runtimeShell} -c 'echo 0 > /proc/sys/net/ipv4/conf/%k/rp_filter || true'"
    '';

    # ── 3. Dummy Loopback 接口（绑定单播 /32 与 /128） ─────────────
    boot.kernelModules = [ "dummy" ];

    # 对于 systemd-networkd 环境
    systemd.network = lib.mkIf config.systemd.network.enable {
      netdevs."10-dn42" = {
        netdevConfig = {
          Name = "dn42";
          Kind = "dummy";
        };
      };
    };

    # 保证在配置网络地址前 dummy 设备已存在并处于 UP 状态
    systemd.services.dn42-dummy = {
      description = "Create DN42 dummy network interface";
      wantedBy = [
        "multi-user.target"
        "network-setup.service"
      ];
      before = [
        "network-setup.service"
        "bird.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.runtimeShell} -c '${pkgs.iproute2}/bin/ip link add dev dn42 type dummy 2>/dev/null || true; ${pkgs.iproute2}/bin/ip link set dev dn42 up 2>/dev/null || true'";
        ExecStop = "${pkgs.runtimeShell} -c '${pkgs.iproute2}/bin/ip link delete dev dn42 2>/dev/null || true'";
      };
    };

    systemd.services.network-addresses-dn42 = {
      wantedBy = [ "multi-user.target" ];
      after = [ "dn42-dummy.service" ];
      wants = [ "dn42-dummy.service" ];
      before = [ "bird.service" ];
    };

    systemd.services.bird = {
      after = [ "network-addresses-dn42.service" ];
      wants = [ "network-addresses-dn42.service" ];
    };

    # ── 集成 dnsmasq：转发 *.<domain> 查询至本集群权威 DNS 与 DN42 Anycast DNS ─────────
    services.dnsmasq.settings.server = [
      "/${cfg.domain}/172.20.232.1"
      "/${cfg.domain}/172.20.0.53"
      "/${cfg.domain}/172.23.0.53"
      "/dn42/172.20.0.53"
      "/dn42/172.23.0.53"
      "/dn42/fd42:d42:d42:54::1"
      "/dn42/fd42:d42:d42:53::1"
    ];

    networking.interfaces.dn42 = {
      ipv4.addresses = [
        {
          address = lib.head (lib.splitString "/" cfg.nodeIpv4);
          prefixLength = lib.toInt (lib.last (lib.splitString "/" cfg.nodeIpv4));
        }
      ];
      ipv6.addresses = [
        {
          address = lib.head (lib.splitString "/" cfg.nodeIpv6);
          prefixLength = lib.toInt (lib.last (lib.splitString "/" cfg.nodeIpv6));
        }
      ];
    };

    # ── 4. 全局 /etc/hosts 映射（默认关闭，完全依靠权威 DNS 动态解析） ────────────
    networking.hosts = lib.mkIf cfg.populateHosts (
      lib.foldr (
        entry: m: m // { ${entry.ip} = (m.${entry.ip} or [ ]) ++ [ entry.hostName ]; }
      ) { } dn42HostList
    );

    # ── 5. 统一 WireGuard 密钥生成服务 ──────────────────────────────
    systemd.services.dn42-wireguard-keygen = {
      description = "Generate WireGuard keys for DN42 if missing";
      wantedBy = [ "multi-user.target" ];
      before = [ "network-pre.target" ];
      path = with pkgs; [
        wireguard-tools
        coreutils
      ];
      script =
        let
          allKeyFiles = lib.unique ([ cfg.privateKeyFile ] ++ cfg.extraKeyFiles);
        in
        ''
          for keyfile in ${lib.concatStringsSep " " (map (k: ''"${k}"'') allKeyFiles)}; do
            case "$keyfile" in
              /var/lib/wireguard/*)
                mkdir -p "$(dirname "$keyfile")"
                chmod 700 "$(dirname "$keyfile")"
                if [ ! -f "$keyfile" ]; then
                  echo "Generating DN42 WireGuard private key at $keyfile..."
                  wg genkey | (umask 077 && cat > "$keyfile")
                fi
                pubfile="''${keyfile%.*}.pub"
                if [ ! -f "$pubfile" ] || [ "$keyfile" -nt "$pubfile" ]; then
                  wg pubkey < "$keyfile" > "$pubfile"
                  chmod 644 "$pubfile"
                  echo "Generated DN42 WireGuard public key at $pubfile"
                fi
                ;;
              *)
                echo "Keyfile $keyfile is external or managed by secret provider (e.g. sops-nix), skipping auto-generation."
                ;;
            esac
          done
        '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ── 6. raw 阶段 notrack: 彻底杜绝 nf_conntrack 将 Fake-TCP 标记为 INVALID ────
    # 覆盖全网所有隧道端口（本机 + 全部对端 + 全部已发布端点），udp/tcp 双协议双向。
    networking.nftables.enable = lib.mkDefault true;
    networking.nftables.tables."dn42-raw-notrack" = {
      family = "inet";
      content = ''
        chain raw_prerouting {
          type filter hook prerouting priority raw; policy accept;
          udp sport { ${portsCsv} } notrack
          udp dport { ${portsCsv} } notrack
          tcp sport { ${portsCsv} } notrack
          tcp dport { ${portsCsv} } notrack
        }

        chain raw_output {
          type filter hook output priority raw; policy accept;
          udp sport { ${portsCsv} } notrack
          udp dport { ${portsCsv} } notrack
          tcp sport { ${portsCsv} } notrack
          tcp dport { ${portsCsv} } notrack
        }
      '';
    };

    # ── 7. DN42 Mesh 入站信任：放行 dn42/dn42x-* 接口上来自 DN42 网段的流量 ────
    # 使 .dn42 SOCKS5(1080)、SSH 等 Mesh 内服务开箱即用；公网接口仍默认拒入。
    networking.firewall.extraInputRules =
      lib.mkIf (cfg.firewall.trustMeshTraffic && config.networking.nftables.enable)
        ''
          iifname { "dn42", "dn42x-*" } ip saddr { 172.20.0.0/14, 172.31.0.0/16, 10.0.0.0/8 } counter accept
          iifname { "dn42", "dn42x-*" } ip6 saddr fd00::/8 counter accept
        '';

    # iptables 回退路径（未启用 nftables 时）
    networking.firewall.extraCommands =
      lib.mkIf (cfg.firewall.trustMeshTraffic && !config.networking.nftables.enable)
        ''
          iptables -A nixos-fw -i dn42+ -s 172.20.0.0/14 -j nixos-fw-accept 2>/dev/null || true
          iptables -A nixos-fw -i dn42+ -s 172.31.0.0/16 -j nixos-fw-accept 2>/dev/null || true
          iptables -A nixos-fw -i dn42+ -s 10.0.0.0/8 -j nixos-fw-accept 2>/dev/null || true
          ip6tables -A nixos-fw -i dn42+ -s fd00::/8 -j nixos-fw-accept 2>/dev/null || true
        '';

    # ── 8. 基础策略路由：底层隧道协议与 DN42 网段强制查 main 表 ────────────
    # 防止 ESP / IKE / Mimic Fake-TCP 底层握手包与 DN42 内网流量被上层
    # TUN/代理策略表捕获造成死锁；全部由数据驱动，不含任何机器名或组件名。
    systemd.services.dn42-policy-routing = {
      description = "DN42 base policy routing (ESP / tunnel-port exemptions and DN42 ranges)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      before = [
        "network.target"
        "bird.service"
      ];
      path = [ pkgs.iproute2 ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        # 幂等清理：先按优先级删除既有规则，避免重复叠加
        for prio in 80 81 90; do
          while ip rule del priority $prio 2>/dev/null; do :; done
          while ip -6 rule del priority $prio 2>/dev/null; do :; done
        done

        # Priority 80: 豁免 ESP 协议，强制查 main 表
        ip rule add ipproto esp lookup main priority 80
        ip -6 rule add ipproto esp lookup main priority 80

        # Priority 81: 豁免全部集群隧道端口，udp/tcp 双协议双向（含 Mimic Fake-TCP）
        for proto in udp tcp; do
          for port in ${lib.concatStringsSep " " (map toString cfg.allClusterTunnelPorts)}; do
            ip rule add ipproto $proto sport $port lookup main priority 81
            ip rule add ipproto $proto dport $port lookup main priority 81
            ip -6 rule add ipproto $proto sport $port lookup main priority 81
            ip -6 rule add ipproto $proto dport $port lookup main priority 81
          done
        done

        # Priority 90: DN42 内部网段与 PMTUD 差错报文强制查 main 表（走 Babel IGP 最优路径）
        ip rule add to 172.20.0.0/14 lookup main priority 90
        ip rule add to 172.31.0.0/16 lookup main priority 90
        ip rule add to 10.0.0.0/8 lookup main priority 90
        ip rule add ipproto icmp lookup main priority 90
        ip -6 rule add to fd00::/8 lookup main priority 90
        ip -6 rule add to fe80::/10 lookup main priority 90
        ip -6 rule add ipproto ipv6-icmp lookup main priority 90
      '';
    };
  };
}
