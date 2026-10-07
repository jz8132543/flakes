{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
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

        ibgp = mkOption {
          type = types.bool;
          default = nodeMeshCfg.ibgp or ((nodeMeshCfg.role or "internal") == "border");
          description = "Whether this node participates in iBGP";
        };

        endpoint = mkOption {
          type = types.nullOr types.str;
          default = nodeMeshCfg.endpoint or null;
          description = "Public WireGuard / IPsec endpoint for this node, or null if behind NAT";
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
      description = "Enable DN42 internal pairwise mesh + Bird 2 Babel IGP";
    };

    backend = mkOption {
      type = types.enum [
        "ipsec"
        "wireguard"
      ];
      default = "ipsec";
      description = "Internal mesh tunnel backend ('ipsec' with XFRM or 'wireguard')";
    };

    ipsec = {
      psk = mkOption {
        type = types.str;
        default = "dn42-internal-mesh-psk-doraim-secure-secret-token";
        description = "Pre-shared key (PSK) used for IKEv2 authentication between mesh nodes";
      };

      pskFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing PSK secret (if null, uses cfg.ipsec.psk)";
      };

      hwOffload = mkOption {
        type = types.enum [
          "auto"
          "crypto"
          "packet"
          "no"
        ];
        default = "auto";
        description = "Hardware crypto/packet offload for IPsec Child SA (auto selects NIC offload when supported)";
      };

      mtu = mkOption {
        type = types.int;
        default = 1400;
        description = "MTU for XFRM interfaces";
      };

      forceUdpEncap = mkOption {
        type = types.bool;
        default = true;
        description = "Force UDP encapsulation for ESP (NAT-T on port 4500) to bypass ISP ESP (protocol 50) blocking";
      };
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
        ibgp = dn42Data.mesh.${hostName}.ibgp or (baseCfg.role == "border");
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
        default = dn42Data.mesh.${hostName}.ibgp or (baseCfg.role == "border");
        description = "Enable iBGP full-mesh across border nodes and configured internal nodes";
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

  config = mkIf (baseCfg.enable && cfg.enable) (mkMerge [
    # ── 1. 通用校验 ──────────────────────────────────────────────────
    {
      assertions = lib.optionals (cfg.backend == "wireguard") (
        mapAttrsToList (peerName: peerCfg: {
          assertion = peerCfg.publicKey != null;
          message = "services.dn42.mesh: WireGuard public key for peer '${peerName}' is missing. Configure 'hosts.${peerName}.dn42_public_key' in lib/data/data.json.";
        }) activePeers
      );
    }

    # ── 2. IPsec / IKEv2 + XFRM 后端实现 ──────────────────────────────
    (mkIf (cfg.backend == "ipsec") {
      boot.kernelModules = [
        "xfrm_interface"
        "esp4"
        "esp6"
      ];

      environment.systemPackages = [ pkgs.strongswan ];

      # XFRM 虚拟网络网卡管理（oneshot 服务，无需强依赖 systemd-networkd，兼容标准脚本网络）
      systemd.services = mapAttrs' (
        peerName: peerCfg:
        let
          ifName = "dn42x-${lib.substring 0 9 peerName}";
          xfrmId = 4200 + (if peerCfg.hostIndex != null then peerCfg.hostIndex else 99);
        in
        nameValuePair ifName {
          description = "DN42 XFRM interface for peer ${peerName}";
          after = [ "network-pre.target" ];
          wants = [ "network-pre.target" ];
          before = [
            "bird.service"
            "strongswan-swanctl.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.iproute2 ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "${ifName}-up" ''
              set -eu
              if ! ip link show ${ifName} >/dev/null 2>&1; then
                ip link add ${ifName} type xfrm if_id ${toString xfrmId}
              fi
              ip link set ${ifName} mtu ${toString cfg.ipsec.mtu} multicast on up
              ip -6 addr replace ${baseCfg.linkLocalIpv6} dev ${ifName}
            '';
            ExecStop = pkgs.writeShellScript "${ifName}-down" ''
              ip link del ${ifName} 2>/dev/null || true
            '';
          };
        }
      ) activePeers;

      # 若系统启用了 systemd-networkd，设置该接口为 Unmanaged 防止被 networkd 重置
      systemd.network.networks = mkIf config.systemd.network.enable (
        mapAttrs' (
          peerName: _:
          let
            ifName = "dn42x-${lib.substring 0 9 peerName}";
          in
          nameValuePair "70-${ifName}" {
            matchConfig.Name = ifName;
            linkConfig.Unmanaged = true;
          }
        ) activePeers
      );

      # Strongswan Swanctl 守护进程配置
      services.strongswan-swanctl = {
        enable = true;
        # 优化说明：
        # 1. threads: 采用 StrongSwan 官方默认线程池 (16 线程)，常驻物理内存仅 ~5.6MB，避免极限低线程导致 VICI IPC 死锁
        # 2. install_routes = no: 禁用 strongswan 自带路由安装，由 Bird 2 全权接管选路
        # 3. install_virtual_ip = no: 禁用虚拟 IP 分配，无状态消耗
        strongswan.extraConfig = ''
          charon {
            install_routes = no
            install_virtual_ip = no
            cisco_unity = no
            send_vendor_id = no
          }
        '';

        swanctl = {
          connections = mapAttrs' (
            peerName: peerCfg:
            let
              peerHost =
                if peerCfg.endpoint != null then lib.head (lib.splitString ":" peerCfg.endpoint) else null;
              xfrmId = 4200 + (if peerCfg.hostIndex != null then peerCfg.hostIndex else 99);
            in
            nameValuePair "mesh-peer-${peerName}" {
              version = 2;
              mobike = true;
              dpd_delay = "15s";
              dpd_timeout = "60s";

              remote_addrs =
                if peerHost != null then
                  [
                    peerHost
                    "%any"
                  ]
                else
                  [ "%any" ];

              encap = cfg.ipsec.forceUdpEncap;

              # 采用现代高效 AEAD 加密套件与 x25519 曲线：
              # 在 AMD/Intel x86_64 具备 AES-NI / AVX-512 / AVX2 指令集下实现近乎零损耗的硬件流水线加速
              proposals = [
                "aes256gcm128-sha256-x25519"
                "chacha20poly1305-sha256-x25519"
                "aes128gcm128-sha256-x25519"
              ];

              local.main = {
                auth = "psk";
                id = "${hostName}.dn42";
              };

              remote.main = {
                auth = "psk";
                id = "${peerName}.dn42";
              };

              children.mesh = {
                esp_proposals = [
                  "aes256gcm128-x25519"
                  "chacha20poly1305-x25519"
                  "aes128gcm128-x25519"
                ];
                local_ts = [
                  "0.0.0.0/0"
                  "::/0"
                ];
                remote_ts = [
                  "0.0.0.0/0"
                  "::/0"
                ];
                if_id_in = toString xfrmId;
                if_id_out = toString xfrmId;
                # hw_offload = auto: 若网卡支持 IPsec Offload 则硬件卸载，否则无缝使用 CPU AES-NI 加速
                hw_offload = cfg.ipsec.hwOffload;
                mode = "tunnel";
                start_action = if peerHost != null then "start" else "trap";
                dpd_action = if peerHost != null then "restart" else "clear";
              };
            }
          ) activePeers;

          secrets.ike = mkIf (cfg.ipsec.pskFile == null) {
            mesh = {
              secret = cfg.ipsec.psk;
            };
          };
        };

        includes = optional (cfg.ipsec.pskFile != null) cfg.ipsec.pskFile;
      };

      # 防火墙放行 IPsec 相关端口、Babel IGP 路由协议与协议号
      networking.firewall = {
        allowedUDPPorts = [
          500
          4500
          6696
        ];
        extraCommands = optionalString (!config.networking.nftables.enable) ''
          ip46tables --append nixos-fw --protocol 50 --jump nixos-fw-accept 2>/dev/null || true
          ip46tables --append nixos-fw --protocol 51 --jump nixos-fw-accept 2>/dev/null || true
        '';
        extraInputRules = optionalString config.networking.nftables.enable ''
          meta l4proto esp counter accept
          meta l4proto ah  counter accept
        '';
      };
    })

    # ── 3. WireGuard 后端实现（保留备选支持） ─────────────────────────
    (mkIf (cfg.backend == "wireguard") {
      networking.wireguard.interfaces = mapAttrs' (
        peerName: peerCfg:
        let
          ifName = "dn42m-${lib.substring 0 9 peerName}";
        in
        nameValuePair ifName {
          ips = [ baseCfg.linkLocalIpv6 ];
          inherit (cfg) listenPort;
          inherit (baseCfg) privateKeyFile;
          allowedIPsAsRoutes = false;
          peers = [
            (
              {
                inherit (peerCfg) publicKey;
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

      systemd.services = mapAttrs' (
        peerName: _:
        let
          ifName = "dn42m-${lib.substring 0 9 peerName}";
        in
        nameValuePair "wireguard-${ifName}" {
          after = [ "dn42-wireguard-keygen.service" ];
          wants = [ "dn42-wireguard-keygen.service" ];
        }
      ) activePeers;

      networking.firewall.allowedUDPPorts = optional (activePeers != { }) cfg.listenPort;
    })

    # ── 4. BIRD 2 动态路由系统 ───────────────────────────────────────
    {
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
          # 严格限制：只向内核注入 DN42 专用内网段，绝不污染外网默认网关或公共互联网路由！
          protocol kernel kernel_v4 {
            ipv4 {
              import none;
              export filter {
                if source = RTS_STATIC then reject;
                if net = 0.0.0.0/0 then reject;
                if ! (net ~ [ 172.20.0.0/14+, 172.31.0.0/16+, 10.0.0.0/8+ ]) then reject;
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
                if net = ::/0 then reject;
                if ! (net ~ [ fd00::/8+ ]) then reject;
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

          # ── Babel IGP 导出过滤器（宣告本机 Loopback 与可选出口路由） ──
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

          # ── Babel IGP 协议：监听所有内部 pairwise 虚拟网卡 ──────────────
          protocol babel dn42_babel {
            ipv4 {
              import all;
              export filter babel_export_v4;
            };
            ipv6 {
              import all;
              export filter babel_export_v6;
            };
            # 兼容监听 IPsec (dn42x-*) 与 WireGuard (dn42m-*) 网卡
            interface "dn42x-*", "dn42m-*" {
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
              mapAttrsToList
                (peerName: peerCfg: ''
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
                '')
                (
                  filterAttrs (
                    n: p: n != hostName && p.ipv6 != null && (p.role == "border" || (p.ibgp or false))
                  ) cfg.nodes
                )
            )}
          ''}
        '';
      };
    }
  ]);
}
