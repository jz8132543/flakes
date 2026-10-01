{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.dn42.router;
  selfData = config.lib.self.data or { };
  thisHostData = selfData.hosts.${config.networking.hostName} or { };

  # /etc/hosts 映射列表：<host>.dn42 -> 各机器独立的 DN42 IP
  dn42HostList = lib.flatten (
    lib.mapAttrsToList (
      name: hostData:
      let
        v4s = hostData.dn42_addresses_v4 or [ ];
        v6s = hostData.dn42_addresses_v6 or [ ];
      in
      lib.lists.map (ip: {
        hostName = "${name}.dn42";
        inherit ip;
      }) (v4s ++ v6s)
    ) (selfData.hosts or { })
  );

  peerSubmodule = types.submodule {
    options = {
      asn = mkOption {
        type = types.int;
        description = "Remote Peer ASN (e.g. 424242xxxx)";
      };
      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Remote WireGuard endpoint (e.g. peer.example.com:51820)";
      };
      listenPort = mkOption {
        type = types.port;
        default = 51820;
        description = "Local WireGuard listen port for this peer";
      };
      publicKey = mkOption {
        type = types.str;
        description = "Remote Peer WireGuard public key";
      };
      privateKeyFile = mkOption {
        type = types.str;
        default = "/var/lib/wireguard/dn42.key";
        description = "Path to local WireGuard private key file";
      };
      ourLinkLocalIpv6 = mkOption {
        type = types.str;
        default = "fe80::115/64";
        description = "Our link-local IPv6 address with mask (e.g. fe80::115/64)";
      };
      peerLinkLocalIpv6 = mkOption {
        type = types.str;
        description = "Peer link-local IPv6 address (e.g. fe80::1234)";
      };
      ourIpv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Our point-to-point IPv4 address with mask (e.g. 172.20.232.3/32)";
      };
      peerIpv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Peer point-to-point IPv4 address";
      };
      latency = mkOption {
        type = types.enum [
          "10ms"
          "40ms"
          "100ms"
          "gt100ms"
        ];
        default = "40ms";
        description = "Estimated link latency for DN42 standard community tagging";
      };
      bandwidth = mkOption {
        type = types.enum [
          "10m"
          "100m"
          "1000m"
        ];
        default = "100m";
        description = "Estimated link bandwidth for DN42 community tagging";
      };
      extendedNextHop = mkOption {
        type = types.bool;
        default = true;
        description = "Enable IPv4 routing over IPv6 link-local Next-Hop (BGP Extended Next Hop / RFC 8950)";
      };
    };
  };

  internalClientSubmodule = types.submodule (
    { name, ... }:
    let
      clientData = selfData.hosts.${name} or { };
      defaultIpv4 =
        if clientData ? dn42_addresses_v4 && clientData.dn42_addresses_v4 != [ ] then
          "${lib.head clientData.dn42_addresses_v4}/32"
        else
          null;
      defaultIpv6 =
        if clientData ? dn42_addresses_v6 && clientData.dn42_addresses_v6 != [ ] then
          "${lib.head clientData.dn42_addresses_v6}/128"
        else
          null;
    in
    {
      options = {
        publicKey = mkOption {
          type = types.str;
          description = "Internal node or laptop WireGuard public key";
        };
        allowedIps = mkOption {
          type = with types; listOf str;
          default = lib.filter (x: x != null) [
            defaultIpv4
            defaultIpv6
          ];
          description = "Allocated DN42 IPs for this node (automatically derived from data.json if name matches host)";
        };
      };
    }
  );
in
{
  options.services.dn42.router = {
    enable = mkEnableOption "DN42 Border Router & Gateway (runs full BGP on nue0, decoupled from Tailscale)";

    asn = mkOption {
      type = types.int;
      default = 4242420115;
      description = "Our DN42 Autonomous System Number";
    };

    ipv4 = mkOption {
      type = types.str;
      default = "172.20.232.0/26";
      description = "Our allocated DN42 IPv4 block";
    };

    ipv6 = mkOption {
      type = types.str;
      default = "fd53:90fd:4bb6::/48";
      description = "Our allocated DN42 IPv6 block";
    };

    routerId = mkOption {
      type = types.str;
      default =
        if thisHostData ? dn42_addresses_v4 && thisHostData.dn42_addresses_v4 != [ ] then
          lib.head thisHostData.dn42_addresses_v4
        else
          "172.20.232.3";
      description = "BGP Router ID (IPv4 address, automatically derived from data.json)";
    };

    nodeIpv4 = mkOption {
      type = types.str;
      default =
        if thisHostData ? dn42_addresses_v4 && thisHostData.dn42_addresses_v4 != [ ] then
          "${lib.head thisHostData.dn42_addresses_v4}/32"
        else
          "172.20.232.3/32";
      description = "Router host IPv4 with mask (automatically derived from data.json)";
    };

    nodeIpv6 = mkOption {
      type = types.str;
      default =
        if thisHostData ? dn42_addresses_v6 && thisHostData.dn42_addresses_v6 != [ ] then
          "${lib.head thisHostData.dn42_addresses_v6}/128"
        else
          "fd53:90fd:4bb6:3::1/128";
      description = "Router host IPv6 with mask (automatically derived from data.json)";
    };

    internalListenPort = mkOption {
      type = types.port;
      default = 51821;
      description = "WireGuard listen port for internal servers and laptops to connect to nue0";
    };

    internalPrivateKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/wireguard/dn42_internal.key";
      description = "Path to WireGuard private key for internal mesh connections";
    };

    peers = mkOption {
      type = types.attrsOf peerSubmodule;
      default = { };
      description = "External DN42 eBGP Peers (WireGuard + BGP)";
    };

    internalNodes = mkOption {
      type = types.attrsOf internalClientSubmodule;
      default = { };
      description = "Internal servers and laptops connecting to nue0 as DN42 nodes";
    };
  };

  config = mkIf cfg.enable {
    # ── 1. 内核转发开启 ────────────────────────────────────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;
    };

    # ── 2. Dummy 虚拟网卡（绑定该路由器的独立单播 IP） ─────────────────────
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

    # ── 3. 全局 /etc/hosts 映射（支持 <host>.dn42 独立访问） ────────────
    networking.hosts = lib.foldr (
      entry: m: m // { ${entry.ip} = (m.${entry.ip} or [ ]) ++ [ entry.hostName ]; }
    ) { } dn42HostList;
  };
}
