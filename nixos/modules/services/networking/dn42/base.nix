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

  # Strict host lookup: eval error if missing!
  thisHostData =
    if selfData ? hosts && selfData.hosts ? ${hostName} then
      selfData.hosts.${hostName}
    else
      throw "services.dn42: Host '${hostName}' not found in data.json under 'hosts'. Please define it in lib/data/data.json.";

  thisHostMesh = dn42Data.mesh.${hostName} or { };

  nodeIpv4Raw =
    if thisHostData ? dn42_addresses_v4 && thisHostData.dn42_addresses_v4 != [ ] then
      lib.head thisHostData.dn42_addresses_v4
    else
      throw "services.dn42: Host '${hostName}' has no 'dn42_addresses_v4' configured in lib/data/data.json.";

  nodeIpv6Raw =
    if thisHostData ? dn42_addresses_v6 && thisHostData.dn42_addresses_v6 != [ ] then
      lib.head thisHostData.dn42_addresses_v6
    else
      throw "services.dn42: Host '${hostName}' has no 'dn42_addresses_v6' configured in lib/data/data.json.";

  hostIndex =
    if thisHostData ? host_indices && thisHostData.host_indices != [ ] then
      lib.head thisHostData.host_indices
    else
      1;

  # Build /etc/hosts mapping from all hosts in data.json: <host>.dn42 -> IP
  dn42HostList = lib.flatten (
    lib.mapAttrsToList (
      name: hData:
      let
        v4s = hData.dn42_addresses_v4 or [ ];
        v6s = hData.dn42_addresses_v6 or [ ];
      in
      lib.lists.map (ip: {
        hostName = "${name}.dn42";
        inherit ip;
      }) (v4s ++ v6s)
    ) (selfData.hosts or { })
  );

  peerAliases = dn42Data.peerAliases or { };
  myAssignedPeers = lib.filterAttrs (_alias: targetHost: targetHost == hostName) peerAliases;
  myPeerAlias = if myAssignedPeers != { } then lib.head (lib.attrNames myAssignedPeers) else null;
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
      "net.ipv4.conf.all.rp_filter" = lib.mkDefault 2;
      "net.ipv4.conf.default.rp_filter" = lib.mkDefault 2;
      # 开启 IPv6 转发时，Linux 内核默认会将 accept_ra 设为 0，导致外网物理网卡丢失 IPv6 默认网关。显式设为 2 确保继续接收路由通告
      "net.ipv6.conf.all.accept_ra" = lib.mkDefault 2;
      "net.ipv6.conf.default.accept_ra" = lib.mkDefault 2;
    };

    networking.firewall.checkReversePath = lib.mkDefault "loose";

    # 为所有动态创建的 dn42* 虚拟网卡设置 loose rp_filter (2)，防止非对称路由丢包
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="net", KERNEL=="dn42*", RUN+="${pkgs.runtimeShell} -c 'echo 2 > /proc/sys/net/ipv4/conf/%k/rp_filter || true'"
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

    # ── 集成 dnsmasq：转发 *.dn42 查询至 DN42 Anycast DNS ─────────
    services.dnsmasq.settings.server = [
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

    # ── 4. 全局 /etc/hosts 映射（支持 <host>.dn42 互访） ────────────
    networking.hosts = lib.foldr (
      entry: m: m // { ${entry.ip} = (m.${entry.ip} or [ ]) ++ [ entry.hostName ]; }
    ) { } dn42HostList;

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
  };
}
