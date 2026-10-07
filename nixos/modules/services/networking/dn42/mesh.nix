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

  cfg = config.services.dn42.mesh;
  baseCfg = config.services.dn42;
  hostName = config.networking.hostName or "unknown";

  selfData = config.lib.self.data or (lib.importJSON ../../../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };

  meshNodeSubmodule = types.submodule (
    { name, ... }:
    let
      nodeHostData = selfData.hosts.${name} or { };
      nodeMeshCfg = dn42Data.mesh.${name} or { };
      v4 =
        if nodeHostData ? dn42_addresses_v4 && nodeHostData.dn42_addresses_v4 != [ ] then
          lib.head nodeHostData.dn42_addresses_v4
        else
          null;
      v6 =
        if nodeHostData ? dn42_addresses_v6 && nodeHostData.dn42_addresses_v6 != [ ] then
          lib.head nodeHostData.dn42_addresses_v6
        else
          null;
      hIdx =
        if nodeHostData ? host_indices && nodeHostData.host_indices != [ ] then
          lib.head nodeHostData.host_indices
        else
          null;
    in
    {
      options = {
        role = mkOption {
          type = types.enum [
            "border"
            "internal"
          ];
          default = nodeMeshCfg.role or "internal";
          description = "Role of this mesh node ('border' or 'internal')";
        };

        endpoint = mkOption {
          type = types.nullOr types.str;
          default = nodeMeshCfg.endpoint or null;
          description = "Public WireGuard endpoint (host:port) for this node, or null if behind NAT";
        };

        listenPort = mkOption {
          type = types.port;
          default = nodeMeshCfg.listenPort or 51821;
          description = "WireGuard listen port";
        };

        publicKey = mkOption {
          type = types.nullOr types.str;
          default = nodeHostData.dn42_public_key or null;
          description = "WireGuard public key of this peer";
        };

        ipv4 = mkOption {
          type = types.nullOr types.str;
          default = v4;
          description = "Loopback IPv4 address of this node";
        };

        ipv6 = mkOption {
          type = types.nullOr types.str;
          default = v6;
          description = "Loopback IPv6 address of this node";
        };

        hostIndex = mkOption {
          type = types.nullOr types.int;
          default = hIdx;
          description = "Host index of this node";
        };

        linkLocalIpv6 = mkOption {
          type = types.str;
          default = if hIdx != null then "fe80::${toString hIdx}/64" else "fe80::1/64";
          description = "Peer link-local IPv6 address";
        };

        persistentKeepalive = mkOption {
          type = types.nullOr types.int;
          default =
            if (cfg.thisNode.endpoint == null && (nodeMeshCfg.endpoint or null != null)) then 25 else null;
          description = "WireGuard persistentKeepalive in seconds (25s on NAT/client side, null on server)";
        };
      };
    }
  );

  # Exclude self
  otherNodes = filterAttrs (n: _: n != hostName) cfg.nodes;

  # Active mesh peers: a pairwise connection can be formed if at least one side has a public endpoint!
  activePeers = filterAttrs (
    _: peer: (cfg.thisNode.endpoint != null) || (peer.endpoint != null)
  ) otherNodes;
in
{
  imports = [ ./base.nix ];

  options.services.dn42.mesh = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable DN42 internal pairwise WireGuard mesh + Bird 2 Babel IGP";
    };

    listenPort = mkOption {
      type = types.port;
      default = dn42Data.mesh.${hostName}.listenPort or 51821;
      description = "WireGuard listen port for mesh interfaces on this node";
    };

    nodes = mkOption {
      type = types.attrsOf meshNodeSubmodule;
      default = dn42Data.mesh or { };
      description = "All nodes participating in the internal DN42 mesh";
    };

    thisNode = mkOption {
      type = meshNodeSubmodule;
      default = {
        inherit (baseCfg) role;
        endpoint = dn42Data.mesh.${hostName}.endpoint or null;
        inherit (cfg) listenPort;
        inherit (baseCfg) publicKey;
        ipv4 = lib.head (lib.splitString "/" baseCfg.nodeIpv4);
        ipv6 = lib.head (lib.splitString "/" baseCfg.nodeIpv6);
        inherit (baseCfg) hostIndex;
      };
      description = "Local node mesh attributes";
    };

    babel = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Babel IGP on mesh interfaces";
      };

      rttMetric = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Babel RTT-based metric (real-time latency + loss routing)";
      };

      rttMin = mkOption {
        type = types.int;
        default = 10;
        description = "Babel RTT min (ms)";
      };

      rttMax = mkOption {
        type = types.int;
        default = 1000;
        description = "Babel RTT max (ms)";
      };

      rttDecay = mkOption {
        type = types.int;
        default = 120;
        description = "Babel RTT decay parameter";
      };
    };

    ibgp = {
      enable = mkOption {
        type = types.bool;
        default = baseCfg.role == "border";
        description = "Enable iBGP full-mesh across border nodes (and optional internal nodes)";
      };

      receiveFullTable = mkOption {
        type = types.bool;
        default = baseCfg.role == "border";
        description = "Receive full BGP routing table over iBGP. If false, only default/exit routes are imported.";
      };
    };

    exportExitRoutes = mkOption {
      type = types.bool;
      default = baseCfg.role == "border";
      description = "Export DN42 summary exit routes (172.20.0.0/14, fd00::/8) into Babel for internal nodes";
    };
  };

  config = mkIf (baseCfg.enable && cfg.enable) {
    # ── 1. 公钥完整性校验（公钥缺失时给出明确指导报错） ────────────
    assertions = mapAttrsToList (peerName: peerCfg: {
      assertion = peerCfg.publicKey != null;
      message = "services.dn42.mesh: Public key for mesh peer '${peerName}' is missing. Please configure 'hosts.${peerName}.dn42_public_key' in lib/data/data.json or 'services.dn42.mesh.nodes.${peerName}.publicKey'.";
    }) activePeers;

    # ── 2. 点对点 Pairwise WireGuard 接口 (dn42-mesh-<peer>) ─────────
    networking.wireguard.interfaces = mapAttrs' (
      peerName: peerCfg:
      nameValuePair "dn42-mesh-${peerName}" {
        ips = [ baseCfg.linkLocalIpv6 ];
        inherit (cfg) listenPort;
        inherit (baseCfg) privateKeyFile;
        peers = [
          (
            {
              inherit (peerCfg) publicKey;
              # AllowedIPs 设置为 0.0.0.0/0 与 ::/0 解耦 Crypto Routing 与动态路由。
              # 注意：此处使用的是原生内核 WireGuard 接口（非 wg-quick），不会在内核主表注入默认路由。
              # 真正的网络选路与下一跳完全由 Bird 动态路由协议（Babel / BGP）掌控。
              allowedIPs = [
                "0.0.0.0/0"
                "::/0"
              ];
            }
            // (optionalAttrs (peerCfg.endpoint != null) {
              inherit (peerCfg) endpoint;
            })
            // (optionalAttrs (peerCfg.persistentKeepalive != null) {
              inherit (peerCfg) persistentKeepalive;
            })
          )
        ];
      }
    ) activePeers;

    # 确保 WireGuard 接口在密钥准备完毕后启动
    systemd.services = mapAttrs' (
      peerName: _:
      nameValuePair "wireguard-dn42-mesh-${peerName}" {
        after = [ "dn42-wireguard-keygen.service" ];
        wants = [ "dn42-wireguard-keygen.service" ];
      }
    ) activePeers;

    # 防火墙放行 WireGuard Mesh 端口
    networking.firewall.allowedUDPPorts = optional (activePeers != { }) cfg.listenPort;

    # ── 3. BIRD 2 路由服务核心配置 ───────────────────────────────────
    services.bird = {
      enable = true;
      package = pkgs.bird2;
      config = lib.mkOrder 200 ''
        log syslog all;
        router id ${baseCfg.routerId};

        define OWNAS = ${toString baseCfg.asn};
        define OWNIPv4 = ${baseCfg.ipv4};
        define OWNIPv6 = ${baseCfg.ipv6};
        define OWN_LOOPBACK_V4 = ${lib.head (lib.splitString "/" baseCfg.nodeIpv4)};
        define OWN_LOOPBACK_V6 = ${lib.head (lib.splitString "/" baseCfg.nodeIpv6)};

        protocol device {
          scan time 10;
        }

        # ── Direct 协议：只监听 dummy 'dn42' 接口导入 Loopback /32 与 /128 ──
        protocol direct direct_dn42 {
          ipv4;
          ipv6;
          interface "dn42";
        }

        # ── 内核路由同步（设置 krt_prefsrc 为本机 Loopback IP） ──────────
        protocol kernel kernel_v4 {
          ipv4 {
            import none;
            export filter {
              if source = RTS_STATIC then reject; # 不向内核下发用于宣告的 unreachable 黑洞路由
              krt_prefsrc = OWN_LOOPBACK_V4;
              accept;
            };
          };
          scan time 20;
          merge paths on;
        }

        protocol kernel kernel_v6 {
          ipv6 {
            import none;
            export filter {
              if source = RTS_STATIC then reject;
              krt_prefsrc = OWN_LOOPBACK_V6;
              accept;
            };
          };
          scan time 20;
          merge paths on;
        }

        ${optionalString cfg.exportExitRoutes ''
          # ── 边界路由向内部注入的 DN42 汇总出口路由 ──
          protocol static static_dn42_exit_v4 {
            ipv4;
            route 172.20.0.0/14 unreachable;
            route 172.31.0.0/16 unreachable;
            route 10.0.0.0/8 unreachable;
          }

          protocol static static_dn42_exit_v6 {
            ipv6;
            route fd00::/8 unreachable;
          }
        ''}

        # ── Babel IGP 导出过滤器（仅宣告 Loopback /32, /128 与可选出口路由） ──
        filter babel_export_v4 {
          if proto = "direct_dn42" && net ~ OWNIPv4 && net.len = 32 then accept;
          ${optionalString cfg.exportExitRoutes ''
            if proto = "static_dn42_exit_v4" then accept;
          ''}
          reject;
        }

        filter babel_export_v6 {
          if proto = "direct_dn42" && net ~ OWNIPv6 && net.len = 128 then accept;
          ${optionalString cfg.exportExitRoutes ''
            if proto = "static_dn42_exit_v6" then accept;
          ''}
          reject;
        }

        # ── Babel IGP 协议：监听所有内部 pairwise 隧道接口 ───────────────
        protocol babel dn42_babel {
          ipv4 {
            import all;
            export filter babel_export_v4;
          };
          ipv6 {
            import all;
            export filter babel_export_v6;
          };
          interface "dn42-mesh-*" {
            type tunnel;
            ${optionalString cfg.babel.rttMetric ''
              rtt cost 1024;
              rtt min ${toString cfg.babel.rttMin} ms;
              rtt max ${toString cfg.babel.rttMax} ms;
              rtt decay ${toString cfg.babel.rttDecay};
            ''}
            check link yes;
          };
        }

        ${optionalString cfg.ibgp.enable ''
          # ── iBGP 全互联（Full-Mesh，基于 Loopback IPv6 + next hop self） ──
          template bgp dn42_ibgp_template {
            local as OWNAS;
            multihop;
            path metric on;
          }

          ${concatStringsSep "\n" (
            mapAttrsToList (peerName: peerCfg: ''
              protocol bgp ibgp_${peerName} from dn42_ibgp_template {
                neighbor ${peerCfg.ipv6} as OWNAS;
                source address OWN_LOOPBACK_V6;

                ipv6 {
                  next hop self;
                  import filter {
                    ${
                      if cfg.ibgp.receiveFullTable then
                        ''
                          accept;
                        ''
                      else
                        ''
                          if net = fd00::/8 then accept;
                          reject;
                        ''
                    }
                  };
                  export filter {
                    if source ~ [ RTS_BGP, RTS_STATIC ] then accept;
                    reject;
                  };
                };

                ipv4 {
                  extended next hop on;
                  next hop self;
                  import filter {
                    ${
                      if cfg.ibgp.receiveFullTable then
                        ''
                          accept;
                        ''
                      else
                        ''
                          if net ~ [ 172.20.0.0/14, 172.31.0.0/16, 10.0.0.0/8 ] then accept;
                          reject;
                        ''
                    }
                  };
                  export filter {
                    if source ~ [ RTS_BGP, RTS_STATIC ] then accept;
                    reject;
                  };
                };
              }
            '') (filterAttrs (n: p: n != hostName && p.role == "border") cfg.nodes)
          )}
        ''}
      '';
    };
  };
}
