{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    concatStringsSep
    optionalString
    mapAttrsToList
    ;

  cfg = config.services.dn42.router;

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
in
{
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 179 ]; # BGP

    # ── DN42 官方 ROA 表自动下载与热重载服务 ───────────────────────────
    systemd.services.dn42-roa-updater = {
      description = "DN42 ROA table auto-updater";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [
        curl
        bird2
        coreutils
      ];
      script = ''
        mkdir -p /var/lib/dn42-roa
        ROA4_URL="https://dn42.burble.dn42/roa/dn42_roa_bird2_4.conf"
        ROA6_URL="https://dn42.burble.dn42/roa/dn42_roa_bird2_6.conf"
        ROA4_FALLBACK="https://dn42.eu/roa/dn42_roa_bird2_4.conf"
        ROA6_FALLBACK="https://dn42.eu/roa/dn42_roa_bird2_6.conf"

        echo "Updating DN42 IPv4 ROA..."
        curl -fsSL --connect-timeout 10 -o /var/lib/dn42-roa/roa_v4.conf.tmp "$ROA4_URL" || \
        curl -fsSL --connect-timeout 10 -o /var/lib/dn42-roa/roa_v4.conf.tmp "$ROA4_FALLBACK" || true

        echo "Updating DN42 IPv6 ROA..."
        curl -fsSL --connect-timeout 10 -o /var/lib/dn42-roa/roa_v6.conf.tmp "$ROA6_URL" || \
        curl -fsSL --connect-timeout 10 -o /var/lib/dn42-roa/roa_v6.conf.tmp "$ROA6_FALLBACK" || true

        if [ -s /var/lib/dn42-roa/roa_v4.conf.tmp ]; then
          mv /var/lib/dn42-roa/roa_v4.conf.tmp /var/lib/dn42-roa/roa_v4.conf
        fi
        if [ -s /var/lib/dn42-roa/roa_v6.conf.tmp ]; then
          mv /var/lib/dn42-roa/roa_v6.conf.tmp /var/lib/dn42-roa/roa_v6.conf
        fi

        if systemctl is-active --quiet bird; then
          birdc configure || true
        fi
      '';
    };

    systemd.timers.dn42-roa-updater = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    # ── Bird 路由服务配置 ─────────────────────────────────────────────
    systemd.services.bird = {
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

    services.bird = {
      enable = true;
      package = pkgs.bird2;
      config = ''
        log syslog all;
        router id ${cfg.routerId};

        define OWNAS = ${toString cfg.asn};
        define OWNIPv4 = ${cfg.ipv4};
        define OWNIPv6 = ${cfg.ipv6};

        # ── ROA 验证表 ──
        include "/var/lib/dn42-roa/roa_v4.conf";
        include "/var/lib/dn42-roa/roa_v6.conf";

        # ── 设备与直连协议 ──
        protocol device {
          scan time 10;
        }

        protocol direct {
          ipv4;
          ipv6;
          interface "dn42", "dn42-internal";
        }

        # ── 本地静态汇总路由宣告 ──
        protocol static static_dn42_v4 {
          ipv4;
          route ${cfg.ipv4} reject;
        }

        protocol static static_dn42_v6 {
          ipv6;
          route ${cfg.ipv6} reject;
        }

        # ── 内核同步协议 ──
        protocol kernel kernel_v4 {
          ipv4 {
            import none;
            export filter {
              if source = RTS_STATIC then reject;
              krt_prefsrc = ${lib.head (lib.splitString "/" cfg.nodeIpv4)};
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
              krt_prefsrc = ${lib.head (lib.splitString "/" cfg.nodeIpv6)};
              accept;
            };
          };
          scan time 20;
          merge paths on;
        }

        # ── 过滤器函数：RFC 与 Bogon 校验 ──
        function is_valid_dn42_v4(prefix net) {
          return net ~ [
            172.20.0.0/14{21,29},
            172.31.0.0/16{21,29},
            10.0.0.0/8{16,29}
          ];
        }

        function is_valid_dn42_v6(prefix net) {
          return net ~ [
            fd00::/8{44,64}
          ];
        }

        # ── eBGP 导入导出过滤器 ──
        filter dn42_export_v4 {
          if proto = "static_dn42_v4" then accept;
          if source = RTS_BGP && net ~ OWNIPv4 then accept;
          reject;
        }

        filter dn42_export_v6 {
          if proto = "static_dn42_v6" then accept;
          if source = RTS_BGP && net ~ OWNIPv6 then accept;
          reject;
        }

        # ── eBGP 邻居模板 ──
        template bgp dn42_peer_template {
          local as OWNAS;
          path metric on;
          direct;
        }

        # ── 自动生成外部 eBGP Peers ──
        ${concatStringsSep "\n" (
          mapAttrsToList (name: p: ''
            # Peer: ${name} (AS${toString p.asn})
            protocol bgp bgp_${name}_v6 from dn42_peer_template {
              neighbor ${p.peerLinkLocalIpv6} % 'dn42-peer-${name}' as ${toString p.asn};

              ipv6 {
                import filter {
                  if !is_valid_dn42_v6(net) then reject;
                  if roa_check(dn42_roa_v6, net, bgp_path.last) = ROA_INVALID then {
                    print "Rejecting ROA invalid IPv6 from ${name}: ", net;
                    reject;
                  }
                  bgp_community.add(${latencyCommunity p.latency});
                  bgp_community.add(${bandwidthCommunity p.bandwidth});
                  accept;
                };
                export filter dn42_export_v6;
              };

              ${optionalString p.extendedNextHop ''
                ipv4 {
                  extended next hop on;
                  import filter {
                    if !is_valid_dn42_v4(net) then reject;
                    if roa_check(dn42_roa_v4, net, bgp_path.last) = ROA_INVALID then {
                      print "Rejecting ROA invalid IPv4 from ${name}: ", net;
                      reject;
                    }
                    bgp_community.add(${latencyCommunity p.latency});
                    bgp_community.add(${bandwidthCommunity p.bandwidth});
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
                    if !is_valid_dn42_v4(net) then reject;
                    if roa_check(dn42_roa_v4, net, bgp_path.last) = ROA_INVALID then {
                      print "Rejecting ROA invalid IPv4 from ${name}: ", net;
                      reject;
                    }
                    bgp_community.add(${latencyCommunity p.latency});
                    bgp_community.add(${bandwidthCommunity p.bandwidth});
                    accept;
                  };
                  export filter dn42_export_v4;
                };
              }
            ''}
          '') cfg.peers
        )}
      '';
    };
  };
}
