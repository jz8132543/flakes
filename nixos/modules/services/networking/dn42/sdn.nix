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

  baseCfg = config.services.dn42;
  cfg = config.services.dn42.sdn;
  hostName = config.networking.hostName or "unknown";

  clientControllers = lib.filter (ip: ip != baseCfg.routerId) cfg.controllers;

  selfData = config.lib.self.data or (lib.importJSON ../../../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };
  edgeNodes = selfData.cdn.edgeNodes or [ ];
  meshEndpoints = dn42Data.mesh or { };
  allHosts = selfData.hosts or { };

  # 动态筛选所有具备 border 角色或开启 ibgp 的骨干节点作为 Controller 候选
  borderNodes = lib.filterAttrs (
    _name: meshCfg: (meshCfg.role or "internal") == "border" || (meshCfg.ibgp or false)
  ) meshEndpoints;

  defaultControllers = lib.unique (
    lib.concatMap (
      name:
      let
        h = allHosts.${name} or { };
      in
      if h ? dn42_addresses_v4 && h.dn42_addresses_v4 != [ ] then
        [ (lib.head h.dn42_addresses_v4) ]
      else
        [ ]
    ) (lib.attrNames borderNodes)
  );

  # 从 data.json 聚合提取全网所有节点的 DN42 IP 与公网 Endpoint 地址
  clusterNodes = lib.mapAttrsToList (
    name: hData:
    let
      dn42Ip = if hData.dn42_addresses_v4 or [ ] != [ ] then lib.head hData.dn42_addresses_v4 else null;
      edgeNode = lib.findFirst (n: n.name == name) null edgeNodes;
      meshNode = meshEndpoints.${name} or { };
      endpointStr =
        if edgeNode != null && (edgeNode.ipv4 or null) != null then
          edgeNode.ipv4
        else if (meshNode.endpoint or null) != null && builtins.isString meshNode.endpoint then
          lib.head (lib.splitString ":" meshNode.endpoint)
        else
          "${name}.dora.im";
    in
    {
      inherit name;
      inherit dn42Ip;
      publicHost = endpointStr;
    }
  ) (lib.filterAttrs (_: h: h.dn42_addresses_v4 or [ ] != [ ]) allHosts);

  clusterNodesJson = builtins.toJSON (lib.filter (n: n.dn42Ip != null) clusterNodes);

  allClusterPublicIps = lib.unique (
    lib.filter (
      ip: ip != null && ip != "" && (builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" ip != null)
    ) ((map (e: e.ipv4 or null) edgeNodes) ++ (map (n: n.publicHost) clusterNodes))
  );

  allClusterPublicV6s = lib.unique (
    lib.filter (ip: ip != null && ip != "" && (lib.hasInfix ":" ip)) (map (e: e.ipv6 or null) edgeNodes)
  );

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      geoip2
      requests
    ]
  );

  # SDN Country Arbiter 算路脚本（仅在 Controller 节点上激活）
  sdnArbiterPkg = pkgs.writeScriptBin "sdn-country-arbiter" ''
    #!${pythonEnv}/bin/python3
    import json
    import math
    import os
    import socket
    import subprocess
    import time
    import geoip2.database

    NODES = json.loads('${clusterNodesJson}')
    GEOIP_PKG = "${cfg.geoIpDatabase}"
    COUNTRY_CIDR_DIR = "${cfg.countryCidrDir}"
    COUNTRY_META_FILE = f"{COUNTRY_CIDR_DIR}/countries_meta.json"
    OUTPUT_CONF = "${cfg.routesOutputFile}"
    LOCAL_HOSTNAME = "${hostName}"

    # 标准国家地理中心坐标锚点（用于 Haversine 球面距离折算光纤延迟）
    COUNTRY_CENTROIDS = {
        "US": (37.0902, -95.7129),
        "CA": (56.1304, -106.3468),
        "GB": (55.3781, -3.4360),
        "DE": (51.1657, 10.4515),
        "FR": (46.2276, 2.2137),
        "NL": (52.1326, 5.2913),
        "JP": (36.2048, 138.2529),
        "SG": (1.3521, 103.8198),
        "HK": (22.3193, 114.1694),
        "TW": (23.6978, 120.9605),
        "KR": (35.9078, 127.7669),
        "AU": (-25.2744, 133.7751),
        "CH": (46.8182, 8.2275),
        "SE": (60.1282, 18.6435),
        "NO": (60.4720, 8.4689),
        "FI": (61.9241, 25.7482),
        "DK": (56.2639, 9.5018),
        "IE": (53.1424, -7.6921),
        "IT": (41.8719, 12.5674),
        "ES": (40.4637, -3.7492),
        "PT": (39.3999, -8.2245),
        "PL": (51.9194, 19.1451),
        "AT": (47.5162, 14.5501),
        "CZ": (49.8175, 15.4730),
        "RU": (61.5240, 105.3188),
        "UA": (48.3794, 31.1656),
        "IN": (20.5937, 78.9629),
        "MY": (4.2105, 101.9758),
        "ID": (-0.7893, 113.9213),
        "TH": (15.8700, 100.9925),
        "VN": (14.0583, 108.2772),
        "PH": (12.8797, 121.7740),
        "BR": (-14.2350, -51.9253),
        "MX": (23.6345, -102.5528),
        "AR": (-38.4161, -63.6167),
        "CL": (-35.6751, -71.5430),
        "ZA": (-30.5595, 22.9375),
        "AE": (23.4241, 53.8478),
        "SA": (23.8859, 45.0792),
        "IL": (31.0461, 34.8516),
        "TR": (38.9637, 35.2433),
        "NZ": (-40.9006, 174.8860),
    }


    def haversine_km(lat1, lon1, lat2, lon2):
        r = 6371.0
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(dlon / 2) ** 2
        )
        return 2 * r * math.asin(math.sqrt(a))


    def ping_rtt(ip):
        try:
            out = subprocess.check_output(
                ["ping", "-c", "2", "-W", "1", ip],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            for line in out.splitlines():
                if "rtt min/avg/max" in line or "round-trip min/avg/max" in line:
                    return float(line.split("/")[4])
        except Exception:
            return None
        return None


    def resolve_ip(host_or_ip):
        try:
            return socket.gethostbyname(host_or_ip)
        except Exception:
            return None


    def find_geoip_db():
        candidates = [
            f"{GEOIP_PKG}/share/dbip/dbip-city-lite.mmdb",
            f"{GEOIP_PKG}/share/dbip-city-lite.mmdb",
            "/var/lib/GeoIP/GeoLite2-City.mmdb",
        ]
        if os.path.isdir(GEOIP_PKG):
            for root, _, files in os.walk(GEOIP_PKG):
                for f in files:
                    if f.endswith(".mmdb"):
                        return os.path.join(root, f)
        elif os.path.isfile(GEOIP_PKG):
            return GEOIP_PKG
        for p in candidates:
            if os.path.exists(p):
                return p
        return None


    def ensure_country_meta():
        os.makedirs(COUNTRY_CIDR_DIR, exist_ok=True)
        if os.path.exists(COUNTRY_META_FILE):
            try:
                with open(COUNTRY_META_FILE) as f:
                    meta = json.load(f)
                    total_cidrs = sum(len(c.get("cidrs", [])) for c in meta.values())
                    if total_cidrs > 0:
                        return meta
            except Exception as e:
                print(f"Warning: could not read {COUNTRY_META_FILE}: {e}")

        meta = {}
        print(f"Scanning for country CIDRs in {COUNTRY_CIDR_DIR}...")
        for iso, (lat, lon) in COUNTRY_CENTROIDS.items():
            cidr_file = os.path.join(COUNTRY_CIDR_DIR, f"{iso.lower()}.cidr")
            cidrs = []
            if os.path.exists(cidr_file) and os.path.getsize(cidr_file) > 0:
                try:
                    with open(cidr_file) as f:
                        cidrs = [
                            line.strip()
                            for line in f
                            if line.strip() and not line.startswith("#")
                        ]
                except Exception:
                    pass
            if cidrs:
                meta[iso] = {"lat": lat, "lon": lon, "cidrs": cidrs}

        total_cidrs = sum(len(c.get("cidrs", [])) for c in meta.values())
        if total_cidrs > 0:
            try:
                with open(COUNTRY_META_FILE, "w") as f:
                    json.dump(meta, f, indent=2)
            except Exception as e:
                print(f"Warning: could not write {COUNTRY_META_FILE}: {e}")
        return meta


    def main():
        mmdb_path = find_geoip_db()
        reader = None
        if mmdb_path and os.path.exists(mmdb_path):
            try:
                reader = geoip2.database.Reader(mmdb_path)
                print(f"Loaded GeoIP City DB from {mmdb_path}")
            except Exception as e:
                print(f"Error opening GeoIP DB {mmdb_path}: {e}")
        else:
            print("Warning: No GeoIP City DB found in package or system!")

        active_nodes = []
        for node in NODES:
            name = node["name"]
            dn42_ip = node.get("dn42Ip")
            if not dn42_ip:
                continue

            if name == LOCAL_HOSTNAME:
                rtt = 0.1
            else:
                rtt = ping_rtt(dn42_ip)

            if rtt is None:
                print(f"Node {name} ({dn42_ip}) unreachable via Babel")
                continue

            public_host = node.get("publicHost")
            public_ip = resolve_ip(public_host) if public_host else None
            if not public_ip:
                print(f"Node {name} host ({public_host}) cannot be resolved")
                continue

            country, lat, lon = None, None, None
            if reader:
                try:
                    resp = reader.city(public_ip)
                    country = resp.country.iso_code
                    lat = resp.location.latitude
                    lon = resp.location.longitude
                except Exception as e:
                    print(f"GeoIP failed for {name} ({public_ip}): {e}")

            if not country or lat is None or lon is None:
                print(
                    f"Warning: Could not determine location for node "
                    f"{name} ({public_ip}), skipping from exit pool"
                )
                continue

            active_nodes.append({
                "name": name,
                "dn42Ip": dn42_ip,
                "publicIp": public_ip,
                "country": country,
                "lat": lat,
                "lon": lon,
                "internal_rtt": rtt,
            })
            print(f"Healthy node {name}: {country}, RTT={rtt:.1f}ms")

        os.makedirs(os.path.dirname(OUTPUT_CONF), exist_ok=True)
        if not active_nodes:
            print("No active nodes available! Writing empty route config.")
            with open(OUTPUT_CONF, "w") as f:
                f.write("# No active SDN nodes\n")
            subprocess.run(["birdc", "configure"], check=False)
            return

        countries = ensure_country_meta()
        gen_time = time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
        lines = [
            "# Auto-generated by SDN Country Arbiter",
            f"# Generated at {gen_time}",
            f"# Active cluster nodes: {len(active_nodes)}",
        ]

        for node in active_nodes:
            lines.append(f"# Node {node['name']} ({node['publicIp']}) exempted")

        total_routes = 0
        for iso_code, c_info in sorted(countries.items()):
            if iso_code == "CN":
                continue

            c_lat = c_info.get("lat")
            c_lon = c_info.get("lon")
            cidrs = c_info.get("cidrs", [])
            if not cidrs or c_lat is None or c_lon is None:
                continue

            same_country_nodes = [
                n for n in active_nodes if n["country"] == iso_code
            ]
            if same_country_nodes:
                best_node = min(
                    same_country_nodes, key=lambda n: n["internal_rtt"]
                )
            else:
                best_node = min(
                    active_nodes,
                    key=lambda n: (
                        haversine_km(c_lat, c_lon, n["lat"], n["lon"]) * 0.01
                    )
                    + n["internal_rtt"],
                )

            for cidr in cidrs:
                lines.append(
                    f"route {cidr} recursive {best_node['dn42Ip']}; "
                    f"# {iso_code} -> {best_node['name']}"
                )
                total_routes += 1

        new_content = "\n".join(lines) + "\n"

        old_content = ""
        if os.path.exists(OUTPUT_CONF):
            try:
                with open(OUTPUT_CONF) as f:
                    old_content = f.read()
            except Exception:
                pass

        if new_content != old_content:
            temp_file = f"{OUTPUT_CONF}.tmp"
            with open(temp_file, "w") as f:
                f.write(new_content)
            os.replace(temp_file, OUTPUT_CONF)
            print(f"Updated {OUTPUT_CONF} with {total_routes} routes.")
            try:
                res = subprocess.run(
                    ["birdc", "configure"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                print(f"birdc configure output: {res.stdout.strip()}")
            except Exception as e:
                print(f"Failed to reload birdc: {e}")
        else:
            print(f"No changes in SDN route topology ({total_routes} routes).")


    if __name__ == "__main__":
        main()
  '';
in
{
  options.services.dn42.sdn = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SDN country-level policy routing, anti-loop rules, and failover";
    };

    isController = mkOption {
      type = types.bool;
      default = baseCfg.role == "border";
      description = "Whether this node acts as an SDN Controller (generates country routes and acts as iBGP Route Reflector)";
    };

    enableClient = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this machine routes its own local outbound traffic through DN42 SDN table 200";
    };

    enableExit = mkOption {
      type = types.bool;
      default = true;
      description = "Whether this node acts as a public internet exit node (NAT masquerade) for forwarded traffic";
    };

    controllers = mkOption {
      type = types.listOf types.str;
      default = defaultControllers;
      description = "DN42 Loopback IPv4 addresses of SDN Controller Route Reflectors";
    };

    table = mkOption {
      type = types.int;
      default = 200;
      description = "Linux routing table number for SDN acceleration";
    };

    tableName = mkOption {
      type = types.str;
      default = "sdn_accel";
      description = "Routing table name registered in rt_tables";
    };

    externalInterface = mkOption {
      type = types.str;
      default = "eth0";
      description = "External WAN interface for SNAT masquerade";
    };

    countryCidrDir = mkOption {
      type = types.str;
      default = "/var/lib/country-cidrs";
      description = "Directory storing aggregated country CIDR files or countries_meta.json";
    };

    routesOutputFile = mkOption {
      type = types.str;
      default = "/var/lib/bird/sdn_routes.conf";
      description = "Output BIRD static routes file for SDN country acceleration";
    };

    geoIpDatabase = mkOption {
      type = types.package;
      default = pkgs.dbip-city-lite;
      description = "GeoIP City database package from nixpkgs (dbip-city-lite)";
    };
  };

  config = mkIf (baseCfg.enable && cfg.enable) {
    # ── 1. 注册内核路由表 200 (sdn_accel) ─────────────────────────────
    networking.iproute2 = mkIf cfg.enableClient {
      enable = true;
      rttablesExtraConfig = ''
        ${toString cfg.table} ${cfg.tableName}
      '';
    };

    # ── 2. XFRM / WireGuard 防环路策略路由与优先级分级调度 ──────────
    systemd.services.sdn-policy-routing = {
      description = "DN42 SDN Policy Routing (table ${toString cfg.table}) and Anti-Loop Rules";
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
        ExecStart = pkgs.writeShellScript "sdn-policy-routing-start" ''
          set -eu
          # 清理旧规则防止重复叠加
          while ip rule del priority 79 2>/dev/null; do :; done
          while ip rule del priority 80 2>/dev/null; do :; done
          while ip rule del priority 81 2>/dev/null; do :; done
          while ip rule del priority 82 2>/dev/null; do :; done
          while ip rule del priority 90 2>/dev/null; do :; done
          while ip rule del priority 100 2>/dev/null; do :; done

          # Priority 79: 豁免所有集群节点的公网 IP 强制查 main 表，彻底杜绝底层通信误入 table 200
          ${lib.concatMapStringsSep "\n" (
            ip: "ip rule add to ${ip}/32 lookup main priority 79"
          ) allClusterPublicIps}

          # Priority 80-82: 豁免 strongSwan (ESP / IKE UDP 34500,4500,500) 与外部 WireGuard 加密底包，强制查 main 表走物理网卡
          ip rule add ipproto esp lookup main priority 80
          ip rule add ipproto udp dport 34500 lookup main priority 81
          ip rule add ipproto udp sport 34500 lookup main priority 81
          ip rule add ipproto udp dport 4500 lookup main priority 81
          ip rule add ipproto udp sport 4500 lookup main priority 81
          ip rule add ipproto udp dport 500 lookup main priority 81
          ip rule add ipproto udp sport 500 lookup main priority 81
          ip rule add fwmark 51820 lookup main priority 82

          # Priority 90: 访问 DN42 内部网段强制查 main 表（走 Babel 内部最优路径）
          ip rule add to 172.20.0.0/14 lookup main priority 90
          ip rule add to 10.0.0.0/8 lookup main priority 90

          # Priority 100: 仅在启用客户端出站加速 (enableClient) 时，优先查 table ${toString cfg.table}
          ${lib.optionalString cfg.enableClient ''
            ip rule add lookup ${cfg.tableName} priority 100
          ''}

          # IPv6 防环与策略路由
          while ip -6 rule del priority 79 2>/dev/null; do :; done
          while ip -6 rule del priority 80 2>/dev/null; do :; done
          while ip -6 rule del priority 81 2>/dev/null; do :; done
          while ip -6 rule del priority 82 2>/dev/null; do :; done
          while ip -6 rule del priority 90 2>/dev/null; do :; done

          ${lib.concatMapStringsSep "\n" (
            ip: "ip -6 rule add to ${ip}/128 lookup main priority 79"
          ) allClusterPublicV6s}

          ip -6 rule add ipproto esp lookup main priority 80
          ip -6 rule add ipproto udp dport 34500 lookup main priority 81
          ip -6 rule add ipproto udp sport 34500 lookup main priority 81
          ip -6 rule add ipproto udp dport 4500 lookup main priority 81
          ip -6 rule add ipproto udp sport 4500 lookup main priority 81
          ip -6 rule add ipproto udp dport 500 lookup main priority 81
          ip -6 rule add ipproto udp sport 500 lookup main priority 81
          ip -6 rule add fwmark 51820 lookup main priority 82
          ip -6 rule add to fd00::/8 lookup main priority 90
        '';
        ExecStop = pkgs.writeShellScript "sdn-policy-routing-stop" ''
          while ip rule del priority 79 2>/dev/null; do :; done
          while ip rule del priority 80 2>/dev/null; do :; done
          while ip rule del priority 81 2>/dev/null; do :; done
          while ip rule del priority 82 2>/dev/null; do :; done
          while ip rule del priority 90 2>/dev/null; do :; done
          while ip rule del priority 100 2>/dev/null; do :; done
          while ip -6 rule del priority 79 2>/dev/null; do :; done
          while ip -6 rule del priority 80 2>/dev/null; do :; done
          while ip -6 rule del priority 81 2>/dev/null; do :; done
          while ip -6 rule del priority 82 2>/dev/null; do :; done
          while ip -6 rule del priority 90 2>/dev/null; do :; done
          ip route flush table ${toString cfg.table} 2>/dev/null || true
        '';
      };
    };

    # ── 3. 全节点公网出口能力（Border + Internal 均可作出口 SNAT） ───
    networking.nat = mkIf cfg.enableExit {
      enable = true;
      externalInterface = lib.mkDefault cfg.externalInterface;
      internalIPs = [
        "172.20.0.0/14"
        "10.0.0.0/8"
      ];
      internalInterfaces = [
        "xfrm+"
        "dn42+"
        "dummy0"
      ];
    };

    # ── 4. BIRD 2 BFD 与 SDN 路由同步配置 ─────────────────────────────
    # 禁用 build 阶段校验，避免在沙箱构建期间因 /var/lib/bird/sdn_routes.conf 尚未生成而报错
    services.bird.checkConfig = lib.mkForce false;

    services.bird.config = lib.mkOrder 250 ''
      # ── SDN 加速：独立内核路由表 ${toString cfg.table} (${cfg.tableName}) ────────────────────
      ipv4 table sdn_table;

      # 毫秒级 BFD 断线检测
      protocol bfd sdn_bfd {
        interface "dn42x-*", "dn42m-*", "xfrm*" {
          min rx interval 100 ms;
          min tx interval 100 ms;
          multiplier 3;
        };
      }

      # 将 master4 中的 DN42 内网路由导入 sdn_table，供静态路由与 BGP 递归解析出口下一跳
      protocol pipe pipe_sdn_dn42 {
        table sdn_table;
        peer table master4;
        import filter {
          if net ~ [ 172.20.0.0/14+, 10.0.0.0/8+ ] then accept;
          reject;
        };
        export none;
      }

      ${lib.optionalString cfg.enableClient ''
        protocol kernel kernel_sdn {
          kernel table ${toString cfg.table};
          persist no;        # BIRD 退出时立即清空内核 table ${toString cfg.table}，毫秒级回退物理网卡
          graceful restart;
          ipv4 {
            table sdn_table;
            import none;
            export filter {
              if proto = "pipe_sdn_dn42" then reject;
              if gw = OWN_LOOPBACK_V4 then reject;
              krt_prefsrc = OWN_LOOPBACK_V4;
              accept;
            };
          };
        }
      ''}

      ${lib.optionalString cfg.isController ''
        # Controller 节点加载外部动态国家级路由表文件
        protocol static global_country_routes {
          ipv4 {
            table sdn_table;
          };
          include "${cfg.routesOutputFile}";
        }

        # 作为 Route Reflector 向全网所有节点下发计算好的出口路由
        template bgp sdn_rr_template {
          local as OWNAS;
          source address OWN_LOOPBACK_V4;
          multihop;
          rr client;
          bfd on;
          ipv4 {
            table sdn_table;
            igp table master4;
            import none;
            export where proto = "global_country_routes";
            next hop keep; # 保留各节点出口真实的 Loopback IP
          };
        }

        ${lib.concatStringsSep "\n" (
          map (peer: ''
            protocol bgp sdn_to_${lib.replaceStrings [ "-" ] [ "_" ] peer.name} from sdn_rr_template {
              neighbor ${peer.dn42Ip} as OWNAS;
            }
          '') (lib.filter (n: n.name != hostName && n.dn42Ip != null) clusterNodes)
        )}
      ''}

      ${lib.optionalString (!cfg.isController) ''
        template bgp sdn_client_template {
          local as OWNAS;
          source address OWN_LOOPBACK_V4;
          multihop;
          bfd on;
          ipv4 {
            table sdn_table;
            igp table master4;
            import all;
            export none;
          };
        }

        ${lib.concatStringsSep "\n" (
          map (ctrlIp: ''
            protocol bgp sdn_from_ctrl_${
              builtins.replaceStrings [ "." ] [ "_" ] ctrlIp
            } from sdn_client_template {
              neighbor ${ctrlIp} as OWNAS;
            }
          '') clientControllers
        )}
      ''}
    '';

    # ── 5. Systemd 终极容灾兜底：BIRD 异常时 100% 清空 table 200 ──────
    systemd.services.bird.serviceConfig = {
      ExecPreStart = [
        "+${pkgs.coreutils}/bin/mkdir -p ${builtins.dirOf cfg.routesOutputFile}"
        "+${pkgs.coreutils}/bin/touch ${cfg.routesOutputFile}"
      ];
      ExecStopPost = [
        "+${pkgs.iproute2}/bin/ip route flush table ${toString cfg.table}"
      ];
      Restart = lib.mkDefault "always";
      RestartSec = lib.mkDefault "3s";
    };

    # ── 6. SDN Controller 巡检服务与定时器（仅在 Controller 上运行） ───
    systemd.services.sdn-country-arbiter = lib.mkIf cfg.isController {
      description = "SDN Country-Level Route Arbiter for BIRD 2";
      after = [
        "bird.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.iputils
        pkgs.bird2
        pkgs.coreutils
        pkgs.iproute2
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sdnArbiterPkg}/bin/sdn-country-arbiter";
      };
    };

    systemd.timers.sdn-country-arbiter = lib.mkIf cfg.isController {
      description = "Periodic inspection and route calculation for SDN Country Arbiter";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "60s";
      };
    };

    # 自动同步/下载聚合国家 CIDR 块服务（初始或每周定期更新）
    systemd.services.sdn-sync-cidrs = lib.mkIf cfg.isController {
      description = "Sync Country CIDR blocks for SDN Country Arbiter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [
        curl
        coreutils
      ];
      script = ''
        mkdir -p ${cfg.countryCidrDir}
        # 使用 jsDelivr CDN 从公开源拉取主要国家 CIDR
        for code in de us jp hk gb fr sg ca au kr nl tw se no fi dk ie it es pt pl at cz ru ua in my id th vn ph br mx ar cl za ae sa il tr nz; do
          f="${cfg.countryCidrDir}/$code.cidr"
          if [ ! -s "$f" ]; then
            echo "Fetching CIDR for $code via jsDelivr CDN..."
            curl -sSfL "https://cdn.jsdelivr.net/gh/ipverse/country-ip-blocks@master/country/$code/ipv4-aggregated.txt" -o "$f.tmp" \
              || curl -sSfL "https://raw.githubusercontent.com/ipverse/country-ip-blocks/master/country/$code/ipv4-aggregated.txt" -o "$f.tmp" \
              || true
            if [ -s "$f.tmp" ]; then
              mv "$f.tmp" "$f"
            else
              rm -f "$f.tmp"
            fi
          fi
        done
        rm -f ${cfg.countryCidrDir}/countries_meta.json
      '';
      serviceConfig = {
        Type = "oneshot";
      };
    };

    systemd.timers.sdn-sync-cidrs = lib.mkIf cfg.isController {
      description = "Weekly sync of Country CIDR blocks";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "7d";
      };
    };
  };
}
