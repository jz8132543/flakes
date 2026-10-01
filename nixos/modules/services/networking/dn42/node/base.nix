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

  cfg = config.services.dn42.node;
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
in
{
  options.services.dn42.node = {
    enable = mkEnableOption "DN42 lightweight client node (<1MB RAM, 0% CPU, no Bird daemon, decoupled from Tailscale)";

    nodeIpv4 = mkOption {
      type = types.str;
      default =
        if thisHostData ? dn42_addresses_v4 && thisHostData.dn42_addresses_v4 != [ ] then
          "${lib.head thisHostData.dn42_addresses_v4}/32"
        else
          "172.20.232.30/32";
      description = "DN42 IPv4 address with mask (automatically derived from data.json for this hostName)";
    };

    nodeIpv6 = mkOption {
      type = types.str;
      default =
        if thisHostData ? dn42_addresses_v6 && thisHostData.dn42_addresses_v6 != [ ] then
          "${lib.head thisHostData.dn42_addresses_v6}/128"
        else
          "fd53:90fd:4bb6:1e::1/128";
      description = "DN42 IPv6 address with mask (automatically derived from data.json for this hostName)";
    };

    gatewayEndpoint = mkOption {
      type = types.str;
      default = "nue0.dora.im:51821";
      description = "Remote WireGuard endpoint of the nue0 border router";
    };

    gatewayPublicKey = mkOption {
      type = types.nullOr types.str;
      default = selfData.hosts.nue0.dn42_public_key or null;
      description = "Public key of the nue0 DN42 gateway WireGuard server";
    };

    privateKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/wireguard/dn42.key";
      description = "Path to local WireGuard private key file";
    };

    extraAllowedIPs = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Additional CIDRs to route through the DN42 gateway";
    };

    dummyInterface = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to create a persistent dummy interface for DN42 IP";
    };
  };

  config = mkIf cfg.enable {
    # ── 1. 全局 /etc/hosts 映射（支持通过 <host>.dn42 访问所有节点） ────
    networking.hosts = lib.foldr (
      entry: m: m // { ${entry.ip} = (m.${entry.ip} or [ ]) ++ [ entry.hostName ]; }
    ) { } dn42HostList;

    # ── 2. 可选 Dummy 接口 ─────────────────────────────────────────────
    networking.interfaces = mkIf cfg.dummyInterface {
      dn42 = {
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
    };
  };
}
