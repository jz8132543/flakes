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

        ourLinkLocalIpv6 = mkOption {
          type = types.str;
          default = baseCfg.linkLocalIpv6;
          description = "Our link-local IPv6 address with mask (e.g. fe80::3/64)";
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

    # ── 1. 外部 Peer WireGuard 虚拟网卡 (dn42-peer-<name>) ───────────
    networking.wireguard.interfaces = mapAttrs' (
      name: p:
      nameValuePair "dn42-peer-${name}" {
        ips = [ p.ourLinkLocalIpv6 ] ++ optional (p.ourIpv4 != null) p.ourIpv4;
        inherit (p) listenPort;
        inherit (p) privateKeyFile;
        peers = [
          (
            {
              inherit (p) publicKey;
              # AllowedIPs 设置为全放行，由 Bird eBGP 与过滤器决定路由
              allowedIPs = [
                "0.0.0.0/0"
                "::/0"
              ];
              persistentKeepalive = 25;
            }
            // (optionalAttrs (p.endpoint != null) {
              inherit (p) endpoint;
            })
          )
        ];
      }
    ) activePeers;

    systemd.services =
      (mapAttrs' (
        name: _:
        nameValuePair "wireguard-dn42-peer-${name}" {
          after = [ "dn42-wireguard-keygen.service" ];
          wants = [ "dn42-wireguard-keygen.service" ];
        }
      ) activePeers)
      // (optionalAttrs cfg.roa.enable {
        dn42-roa-updater = {
          description = "DN42 ROA table auto-updater with configuration pre-check";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            curl
            bird2
            coreutils
          ];
          script = ''
            mkdir -p /var/lib/dn42-roa
            ROA4_TMP="/var/lib/dn42-roa/roa_v4.conf.tmp"
            ROA6_TMP="/var/lib/dn42-roa/roa_v6.conf.tmp"

            fetch_file() {
              local out="$1"
              local url1="$2"
              local url2="$3"
              if curl -fsSL --connect-timeout 10 --max-time 30 -o "$out" "$url1"; then
                return 0
              fi
              echo "Primary URL ($url1) failed, trying fallback ($url2)..." >&2
              if curl -fsSL --connect-timeout 10 --max-time 30 -o "$out" "$url2"; then
                return 0
              fi
              echo "Both primary and fallback failed for $out" >&2
              return 1
            }

            echo "Fetching DN42 IPv4 ROA..."
            fetch_file "$ROA4_TMP" "https://dn42.burble.dn42/roa/dn42_roa_bird2_4.conf" "https://dn42.eu/roa/dn42_roa_bird2_4.conf"

            echo "Fetching DN42 IPv6 ROA..."
            fetch_file "$ROA6_TMP" "https://dn42.burble.dn42/roa/dn42_roa_bird2_6.conf" "https://dn42.eu/roa/dn42_roa_bird2_6.conf"

            if [ ! -s "$ROA4_TMP" ] || [ ! -s "$ROA6_TMP" ]; then
              echo "ERROR: Downloaded ROA file is empty, aborting update." >&2
              exit 1
            fi

            # 备份旧配置
            cp -f /var/lib/dn42-roa/roa_v4.conf /var/lib/dn42-roa/roa_v4.conf.bak 2>/dev/null || true
            cp -f /var/lib/dn42-roa/roa_v6.conf /var/lib/dn42-roa/roa_v6.conf.bak 2>/dev/null || true

            # 移动新文件
            mv "$ROA4_TMP" /var/lib/dn42-roa/roa_v4.conf
            mv "$ROA6_TMP" /var/lib/dn42-roa/roa_v6.conf

            # 若 BIRD 运行中，先执行语法检查再重载，失败则回滚并退出
            if systemctl is-active --quiet bird; then
              echo "Checking BIRD configuration with new ROA..."
              if birdc configure check; then
                echo "Configuration valid, applying new ROA tables..."
                birdc configure
              else
                echo "ERROR: birdc configure check failed with new ROA! Rolling back..." >&2
                cp -f /var/lib/dn42-roa/roa_v4.conf.bak /var/lib/dn42-roa/roa_v4.conf 2>/dev/null || true
                cp -f /var/lib/dn42-roa/roa_v6.conf.bak /var/lib/dn42-roa/roa_v6.conf 2>/dev/null || true
                exit 1
              fi
            fi
            echo "DN42 ROA tables updated successfully."
          '';
        };

        bird = {
          preStart = ''
            mkdir -p /var/lib/dn42-roa
            if [ ! -f /var/lib/dn42-roa/roa_v4.conf ]; then
              echo "roa4 table dn42_roa_v4;" > /var/lib/dn42-roa/roa_v4.conf
            fi
            if [ ! -f /var/lib/dn42-roa/roa_v6.conf ]; then
              echo "roa6 table dn42_roa_v6;" > /var/lib/dn42-roa/roa_v6.conf
            fi
          '';
        };
      });

    # 防火墙端口放行
    networking.firewall.allowedUDPPorts = mapAttrsToList (_: p: p.listenPort) activePeers;
    networking.firewall.allowedTCPPorts = [ 179 ]; # BGP

    systemd.timers.dn42-roa-updater = mkIf cfg.roa.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.roa.updateInterval;
        Persistent = true;
      };
    };

    # ── 3. BIRD 2 外部 BGP Peer 与过滤规则 ───────────────────────────
    services.bird.config = lib.mkOrder 300 ''
      # ── ROA 验证表导入 ──
      include "/var/lib/dn42-roa/roa_v4.conf";
      include "/var/lib/dn42-roa/roa_v6.conf";

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
        mapAttrsToList (name: p: ''
          # Peer: ${name} (AS${toString p.asn})
          protocol bgp bgp_${name}_v6 from dn42_peer_template {
            neighbor ${p.peerLinkLocalIpv6} % 'dn42-peer-${name}' as ${toString p.asn};

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
            protocol bgp bgp_${name}_v4 from dn42_peer_template {
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
        '') activePeers
      )}
    '';
  };
}
