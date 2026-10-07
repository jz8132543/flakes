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
    mapAttrs'
    mapAttrsToList
    nameValuePair
    optional
    optionalAttrs
    optionalString
    concatStringsSep
    filterAttrs
    ;

  cfg = config.services.dn42.edge;
  baseCfg = config.services.dn42;
  hostName = config.networking.hostName or "unknown";

  selfData = config.lib.self.data or (lib.importJSON ../../../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };

  # Peer submodule for external eBGP peers
  peerSubmodule = types.submodule (
    { config, name, ... }:
    let
      rawPeer = dn42Data.externalPeers.${name} or { };
    in
    {
      options = {
        host = mkOption {
          type = types.nullOr types.str;
          default = rawPeer.host or null;
          description = "Specific border router hostname this peer belongs to (null = all/current host)";
        };

        asn = mkOption {
          type = types.int;
          default = rawPeer.asn;
          description = "Remote Peer ASN (e.g. 424242xxxx)";
        };

        endpoint = mkOption {
          type = types.nullOr types.str;
          default = rawPeer.endpoint or null;
          description = "Remote WireGuard endpoint (e.g. peer.example.com:51820)";
        };

        listenPort = mkOption {
          type = types.port;
          default = rawPeer.listenPort or 51820;
          description = "Local WireGuard listen port for this peer";
        };

        publicKey = mkOption {
          type = types.str;
          default = rawPeer.publicKey;
          description = "Remote Peer WireGuard public key";
        };

        privateKeyFile = mkOption {
          type = types.str;
          default = baseCfg.privateKeyFile;
          description = "Path to local WireGuard private key file for this peer";
        };

        presharedKeyFile = mkOption {
          type = types.nullOr types.str;
          default = rawPeer.presharedKeyFile or null;
          description = "Optional WireGuard preshared key file for this external peer";
        };

        ourLinkLocalIpv6 = mkOption {
          type = types.str;
          default =
            if (rawPeer.ourLinkLocal or null) != null then
              if lib.hasInfix "/" rawPeer.ourLinkLocal then rawPeer.ourLinkLocal else "${rawPeer.ourLinkLocal}/64"
            else if (rawPeer.ourLinkLocalIpv6 or null) != null then
              if lib.hasInfix "/" rawPeer.ourLinkLocalIpv6 then
                rawPeer.ourLinkLocalIpv6
              else
                "${rawPeer.ourLinkLocalIpv6}/64"
            else
              baseCfg.linkLocalIpv6;
          description = "Our link-local IPv6 address with mask (e.g. fe80::3/64)";
        };

        ourLinkLocal = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Our link-local IPv6 address from data.json";
        };

        linkLocal = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Peer link-local IPv6 address from data.json";
        };

        peerLinkLocalIpv6 = mkOption {
          type = types.str;
          default =
            if config.linkLocal != null then
              config.linkLocal
            else
              rawPeer.linkLocal or (rawPeer.peerLinkLocalIpv6 or "fe80::1");
          description = "Peer link-local IPv6 address (e.g. fe80::1234)";
        };

        ourIpv4 = mkOption {
          type = types.nullOr types.str;
          default = rawPeer.ourIpv4 or null;
          description = "Our point-to-point IPv4 address with mask (e.g. 172.20.232.3/32)";
        };

        peerIpv4 = mkOption {
          type = types.nullOr types.str;
          default = rawPeer.peerIpv4 or null;
          description = "Peer point-to-point IPv4 address";
        };

        latency = mkOption {
          type = types.enum [
            "10ms"
            "40ms"
            "100ms"
            "gt100ms"
          ];
          default = rawPeer.latency or "40ms";
          description = "Estimated link latency for DN42 standard community tagging";
        };

        bandwidth = mkOption {
          type = types.enum [
            "10m"
            "100m"
            "1000m"
          ];
          default = rawPeer.bandwidth or "100m";
          description = "Estimated link bandwidth for DN42 community tagging";
        };

        crypto = mkOption {
          type = types.enum [
            "unsafe"
            "des"
            "aes"
            "wireguard"
          ];
          default = rawPeer.crypto or "wireguard";
          description = "Link encryption type for DN42 community tagging";
        };

        extendedNextHop = mkOption {
          type = types.bool;
          default = rawPeer.extendedNextHop or true;
          description = "Enable IPv4 routing over IPv6 link-local Next-Hop (BGP Extended Next Hop / RFC 8950)";
        };
      };
    }
  );

  # Filter peers matching this border node
  activePeers = filterAttrs (_: p: p.host == null || p.host == hostName) cfg.peers;

  latencyCommunity =
    l:
    {
      "10ms" = "(64511, 1)";
      "40ms" = "(64511, 2)";
      "100ms" = "(64511, 3)";
      "gt100ms" = "(64511, 4)";
    }
    .${l};

  bandwidthCommunity =
    b:
    {
      "10m" = "(64511, 21)";
      "100m" = "(64511, 22)";
      "1000m" = "(64511, 23)";
    }
    .${b};

  cryptoCommunity =
    c:
    {
      "unsafe" = "(64511, 31)";
      "des" = "(64511, 32)";
      "aes" = "(64511, 33)";
      "wireguard" = "(64511, 34)";
    }
    .${c};
in
{
  imports = [
    ./base.nix
    ./mesh.nix
  ];

  options.services.dn42.edge = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DN42 external eBGP peering & ROA validation (border node only)";
    };

    peers = mkOption {
      type = types.attrsOf peerSubmodule;
      default = dn42Data.externalPeers or { };
      description = "External DN42 eBGP Peers (WireGuard + MP-BGP)";
    };

    roa = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic ROA download and validation";
      };

      updateInterval = mkOption {
        type = types.str;
        default = "1h";
        description = "Systemd timer interval for ROA table download";
      };

      strict = mkOption {
        type = types.bool;
        default = false;
        description = "If true, reject ROA_UNKNOWN routes as well. If false, only reject ROA_INVALID (DN42 standard).";
      };
    };

    staticAggregate = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Generate unreachable static routes for our IPv4/IPv6 CIDR blocks for eBGP export";
      };
    };
  };

  config = mkIf (baseCfg.enable && cfg.enable) {
    # 确保外部 Peer 的私钥纳入统一生成管理范围
    services.dn42.extraKeyFiles = mapAttrsToList (_: p: p.privateKeyFile) activePeers;

    # ── 1. 外部 Peer WireGuard 虚拟网卡 (dn42-<name>) ───────────
    # Linux IFNAMSIZ = 16，网络接口名最长 15 字符
    # 格式为 "dn42-" (5 字符) + Peer 名字截取前 10 字符，总长不超过 15 字符
    networking.wireguard.interfaces = mapAttrs' (
      name: p:
      let
        ifName = "dn42-${lib.substring 0 10 name}";
      in
      nameValuePair ifName {
        ips = [ p.ourLinkLocalIpv6 ] ++ optional (p.ourIpv4 != null) p.ourIpv4;
        inherit (p) listenPort;
        inherit (p) privateKeyFile;
        # 必须禁用自动添加路由！BGP 网络中路由全权由 Bird 负责，否则 WireGuard 会将 0.0.0.0/0 与 ::/0 写入系统路由表从而冲垮物理公网网关！
        allowedIPsAsRoutes = false;
        peers = [
          (
            {
              inherit (p) publicKey;
              # 仅允许 DN42、ULA 与 Link-Local 流量，避免污染公网路由或流量逃逸
              allowedIPs = [
                "fe80::/10"
                "172.20.0.0/14"
                "172.31.0.0/16"
                "10.0.0.0/8"
                "fd00::/8"
              ];
              persistentKeepalive = 25;
            }
            // (optionalAttrs (p.endpoint != null) {
              inherit (p) endpoint;
            })
            // (optionalAttrs (p.presharedKeyFile != null) {
              inherit (p) presharedKeyFile;
            })
          )
        ];
      }
    ) activePeers;

    systemd.services =
      (mapAttrs' (
        name: _:
        let
          ifName = "dn42-${lib.substring 0 10 name}";
        in
        nameValuePair "wireguard-${ifName}" {
          after = [
            "dn42-wireguard-keygen.service"
            "dnsmasq.service"
            "network-online.target"
          ];
          wants = [
            "dn42-wireguard-keygen.service"
            "dnsmasq.service"
            "network-online.target"
          ];
        }
      ) activePeers)
      // (optionalAttrs cfg.roa.enable {
        stayrtr-dn42 = {
          description = "StayRTR RPKI server for DN42";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            DynamicUser = true;
            ExecStart = "${pkgs.stayrtr}/bin/stayrtr -cache=https://dn42.burble.com/roa/dn42_roa_46.json -checktime=false -bind=127.0.0.1:8282 -metrics.addr=127.0.0.1:9847 -rtr.retry=10";
            Restart = "always";
            RestartSec = "10s";
          };
        };
      });

    # 防火墙端口放行
    networking.firewall.allowedUDPPorts = mapAttrsToList (_: p: p.listenPort) activePeers;
    networking.firewall.allowedTCPPorts = [ 179 ]; # BGP

    # ── 3. BIRD 2 外部 BGP Peer 与过滤规则 ───────────────────────────
    services.bird.config = lib.mkOrder 300 ''
      # ── ROA 验证表导入（RPKI via StayRTR） ──
      roa4 table dn42_roa_v4;
      roa6 table dn42_roa_v6;

      ${optionalString cfg.roa.enable ''
        protocol rpki rtr_dn42 {
          roa4 { table dn42_roa_v4; };
          roa6 { table dn42_roa_v6; };
          remote "127.0.0.1" port 8282;
          retry keep 90;
          refresh keep 900;
          expire keep 172800;
        }
      ''}

      ${optionalString cfg.staticAggregate.enable ''
        # ── 本地静态汇总黑洞路由（用于 BGP 聚合宣告） ──
        protocol static static_dn42_v4 {
          ipv4;
          route ${baseCfg.ipv4} unreachable;
        }

        protocol static static_dn42_v6 {
          ipv6;
          route ${baseCfg.ipv6} unreachable;
        }
      ''}

      # ── 前缀合法性校验函数（RFC / Bogon 校验） ──
      function is_valid_dn42_v4() -> bool {
        return net ~ [
          172.20.0.0/14{21,29},
          172.20.0.0/24{28,32},
          172.21.0.0/24{28,32},
          172.22.0.0/24{28,32},
          172.23.0.0/24{28,32},
          172.31.0.0/16{21,29},
          10.0.0.0/8{16,29}
        ];
      }

      function is_valid_dn42_v6() -> bool {
        return net ~ [
          fd00::/8{44,64}
        ];
      }

      # ── eBGP 导出过滤器 ──
      filter dn42_export_v4 {
        if proto = "static_dn42_v4" then accept;
        if source = RTS_BGP && is_valid_dn42_v4() then accept;
        reject;
      }

      filter dn42_export_v6 {
        if proto = "static_dn42_v6" then accept;
        if source = RTS_BGP && is_valid_dn42_v6() then accept;
        reject;
      }

      # ── eBGP 邻居模板 ──
      template bgp dn42_peer_template {
        local as OWNAS;
        path metric on;
        direct;
      }

      # ── 外部 eBGP Peers ──
      ${concatStringsSep "\n" (
        mapAttrsToList (
          name: p:
          let
            ifName = "dn42-${lib.substring 0 10 name}";
            protoName = lib.replaceStrings [ "-" ] [ "_" ] name;
          in
          ''
            # Peer: ${name} (AS${toString p.asn})
            protocol bgp bgp_${protoName}_v6 from dn42_peer_template {
              neighbor ${p.peerLinkLocalIpv6} % '${ifName}' as ${toString p.asn};
              source address ${lib.head (lib.splitString "/" p.ourLinkLocalIpv6)};

              ipv6 {
                import filter {
                  if !is_valid_dn42_v6() then reject;
                  if net ~ OWNIPv6 then reject;
                  ${
                    if cfg.roa.strict then
                      ''
                        if roa_check(dn42_roa_v6, net, bgp_path.last) != ROA_VALID then {
                          print "Rejecting ROA invalid/unknown IPv6 from ${name}: ", net;
                          reject;
                        }
                      ''
                    else
                      ''
                        if roa_check(dn42_roa_v6, net, bgp_path.last) = ROA_INVALID then {
                          print "Rejecting ROA invalid IPv6 from ${name}: ", net;
                          reject;
                        }
                      ''
                  }
                  bgp_community.add(${latencyCommunity p.latency});
                  bgp_community.add(${bandwidthCommunity p.bandwidth});
                  bgp_community.add(${cryptoCommunity p.crypto});
                  accept;
                };
                export filter dn42_export_v6;
              };

              ${optionalString p.extendedNextHop ''
                ipv4 {
                  extended next hop on;
                  import filter {
                    if !is_valid_dn42_v4() then reject;
                    if net ~ OWNIPv4 then reject;
                    ${
                      if cfg.roa.strict then
                        ''
                          if roa_check(dn42_roa_v4, net, bgp_path.last) != ROA_VALID then {
                            print "Rejecting ROA invalid/unknown IPv4 from ${name}: ", net;
                            reject;
                          }
                        ''
                      else
                        ''
                          if roa_check(dn42_roa_v4, net, bgp_path.last) = ROA_INVALID then {
                            print "Rejecting ROA invalid IPv4 from ${name}: ", net;
                            reject;
                          }
                        ''
                    }
                    bgp_community.add(${latencyCommunity p.latency});
                    bgp_community.add(${bandwidthCommunity p.bandwidth});
                    bgp_community.add(${cryptoCommunity p.crypto});
                    accept;
                  };
                  export filter dn42_export_v4;
                };
              ''}
            }

            ${optionalString (!p.extendedNextHop && p.peerIpv4 != null) ''
                protocol bgp bgp_${protoName}_v4 from dn42_peer_template {
                  neighbor ${p.peerIpv4} as ${toString p.asn};
                ipv4 {
                  import filter {
                    if !is_valid_dn42_v4() then reject;
                    if net ~ OWNIPv4 then reject;
                    ${
                      if cfg.roa.strict then
                        ''
                          if roa_check(dn42_roa_v4, net, bgp_path.last) != ROA_VALID then {
                            print "Rejecting ROA invalid/unknown IPv4 from ${name}: ", net;
                            reject;
                          }
                        ''
                      else
                        ''
                          if roa_check(dn42_roa_v4, net, bgp_path.last) = ROA_INVALID then {
                            print "Rejecting ROA invalid IPv4 from ${name}: ", net;
                            reject;
                          }
                        ''
                    }
                    bgp_community.add(${latencyCommunity p.latency});
                    bgp_community.add(${bandwidthCommunity p.bandwidth});
                    bgp_community.add(${cryptoCommunity p.crypto});
                    accept;
                  };
                  export filter dn42_export_v4;
                };
              }
            ''}
          ''
        ) activePeers
      )}
    '';
  };
}
