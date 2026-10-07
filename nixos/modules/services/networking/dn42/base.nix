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

    privateKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/wireguard/dn42.key";
      description = "Path to local WireGuard private key file (supports /run/secrets/...)";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = thisHostData.dn42_public_key or null;
      description = "WireGuard public key of this host (read from data.json)";
    };

    extraKeyFiles = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Additional WireGuard private key files to automatically generate if under /var/lib/wireguard/";
    };
  };

  config = mkIf cfg.enable {
    # ── 1. 基础系统工具 ─────────────────────────────────────────────
    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.bird2
    ];

    # ── 2. 内核转发与宽松反向路径过滤（sysctl） ─────────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;
      "net.ipv4.conf.all.rp_filter" = lib.mkDefault 2;
      "net.ipv4.conf.default.rp_filter" = lib.mkDefault 2;
    };

    networking.firewall.checkReversePath = lib.mkDefault "loose";

    # 为所有动态创建的 dn42* 虚拟网卡设置 loose rp_filter (2)，防止非对称路由丢包
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="net", KERNEL=="dn42*", RUN+="${pkgs.runtimeShell} -c 'echo 2 > /proc/sys/net/ipv4/conf/%k/rp_filter || true'"
    '';

    # ── 3. Dummy Loopback 接口（绑定单播 /32 与 /128） ─────────────
    networking.interfaces.dn42 = {
      virtual = true;
      virtualType = "dummy";
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
