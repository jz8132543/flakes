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

  isAccelerated = cfg.enableAcceleration || cfg.enableClient;

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
    lib.filter
      (ip: ip != null && ip != "" && (builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" ip != null))
      (
        (map (e: e.ipv4 or null) edgeNodes)
        ++ (map (n: n.publicHost) clusterNodes)
        ++ (lib.flatten (lib.mapAttrsToList (_: h: h.endpoints_v4 or [ ]) allHosts))
      )
  );

  allClusterPublicV6s = lib.unique (
    lib.filter (ip: ip != null && ip != "" && (lib.hasInfix ":" ip)) (
      (map (e: e.ipv6 or null) edgeNodes)
      ++ (lib.flatten (lib.mapAttrsToList (_: h: h.endpoints_v6 or [ ]) allHosts))
    )
  );

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      maxminddb
      geoip2
      requests
    ]
  );

  # SDN Country Arbiter 算路脚本（仅在 Controller 节点上激活）
  sdnArbiterPkg = pkgs.writeScriptBin "sdn-country-arbiter" ''
    #!${pythonEnv}/bin/python3
    import collections
    import glob
    import ipaddress
    import json
    import math
    import os
    import re
    import socket
    import subprocess
    import time
    import maxminddb

    NODES = json.loads('${clusterNodesJson}')
    GEOIP_PKG = "${cfg.geoIpDatabase}"
    COUNTRY_CIDR_DIR = "${cfg.countryCidrDir}"
    OUTPUT_CONF = "${cfg.routesOutputFile}"
    LOCAL_HOSTNAME = "${hostName}"

    # 紧凑 IATA 机场前缀基准表（用于节点命名校准、防商家广播 IP 漂移及 Fallback）
    IATA_LOCATIONS = {
        "fra": {"country": "DE", "lat": 50.1109, "lon": 8.6821, "city": "Frankfurt"},
        "nue": {"country": "DE", "lat": 49.4521, "lon": 11.0767, "city": "Nuremberg"},
        "tyo": {"country": "JP", "lat": 35.6762, "lon": 139.6503, "city": "Tokyo"},
        "sjc": {"country": "US", "lat": 37.3382, "lon": -121.8863, "city": "San Jose"},
        "dfw": {"country": "US", "lat": 32.7767, "lon": -96.7970, "city": "Dallas"},
        "ams": {"country": "NL", "lat": 52.3676, "lon": 4.9041, "city": "Amsterdam"},
        "vie": {"country": "AT", "lat": 48.2082, "lon": 16.3738, "city": "Vienna"},
        "hkg": {"country": "HK", "lat": 22.3193, "lon": 114.1694, "city": "Hong Kong"},
        "can": {"country": "CN", "lat": 23.1291, "lon": 113.2644, "city": "Guangzhou"},
        "xiy": {"country": "CN", "lat": 34.3416, "lon": 108.9398, "city": "Xi'an"},
        "isk": {"country": "JP", "lat": 34.6937, "lon": 135.5023, "city": "Osaka"},
        "sin": {"country": "SG", "lat": 1.3521, "lon": 103.8198, "city": "Singapore"},
        "lon": {"country": "GB", "lat": 51.5074, "lon": -0.1278, "city": "London"},
        "lhr": {"country": "GB", "lat": 51.4700, "lon": -0.4543, "city": "London"},
        "par": {"country": "FR", "lat": 48.8566, "lon": 2.3522, "city": "Paris"},
        "cdg": {"country": "FR", "lat": 49.0097, "lon": 2.5479, "city": "Paris"},
        "syd": {"country": "AU", "lat": -33.8688, "lon": 151.2093, "city": "Sydney"},
        "sea": {"country": "US", "lat": 47.6062, "lon": -122.3321, "city": "Seattle"},
        "lax": {"country": "US", "lat": 33.9416, "lon": -118.4085, "city": "Los Angeles"},
        "ord": {"country": "US", "lat": 41.9742, "lon": -87.9073, "city": "Chicago"},
        "iad": {"country": "US", "lat": 38.9531, "lon": -77.4565, "city": "Washington"},
        "ewr": {"country": "US", "lat": 40.6895, "lon": -74.1745, "city": "Newark"},
        "jfk": {"country": "US", "lat": 40.6413, "lon": -73.7781, "city": "New York"},
        "icn": {"country": "KR", "lat": 37.4602, "lon": 126.4407, "city": "Seoul"},
        "tpe": {"country": "TW", "lat": 25.0797, "lon": 121.2342, "city": "Taipei"},
        "pek": {"country": "CN", "lat": 40.0799, "lon": 116.6031, "city": "Beijing"},
        "pvg": {"country": "CN", "lat": 31.1443, "lon": 121.8083, "city": "Shanghai"},
        "sha": {"country": "CN", "lat": 31.1979, "lon": 121.3363, "city": "Shanghai"},
        "szx": {"country": "CN", "lat": 22.6393, "lon": 113.8107, "city": "Shenzhen"},
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


    def check_wan_health():
        """Verify local external WAN connectivity to prevent WAN Blackhole"""
        for target in ["1.1.1.1", "8.8.8.8"]:
            try:
                subprocess.check_call(
                    ["ping", "-c", "1", "-W", "2", target],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return True
            except Exception:
                pass
        return False


    def get_swanctl_remote_ips():
        """Extract active IKE SA remote-host IPs for NAT / mobile clients from swanctl --list-sas"""
        remote_ips = {}
        try:
            out = subprocess.check_output(
                ["swanctl", "--list-sas"], text=True, stderr=subprocess.DEVNULL
            )
            current_peer = None
            for line in out.splitlines():
                line = line.strip()
                if line.startswith("mesh-peer-"):
                    pname = line.split(":")[0].replace("mesh-peer-", "")
                    current_peer = pname.split("-")[0]
                elif current_peer and ("remote:" in line or "remote-host:" in line):
                    parts = line.split()
                    for part in parts:
                        m = re.match(r"^(\d+\.\d+\.\d+\.\d+)$", part)
                        if m:
                            remote_ips[current_peer] = m.group(1)
                            break
        except Exception:
            pass
        return remote_ips


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


    def main():
        mmdb_path = find_geoip_db()
        reader = None
        if mmdb_path and os.path.exists(mmdb_path):
            try:
                reader = maxminddb.open_database(mmdb_path)
                print(f"Loaded GeoIP City DB from {mmdb_path}")
            except Exception as e:
                print(f"Error opening GeoIP DB {mmdb_path}: {e}")
        else:
            print("Warning: No GeoIP City DB found in package or system!")

        # Check local node WAN health
        local_wan_ok = check_wan_health()
        if not local_wan_ok:
            print("Warning: Local WAN probe to 1.1.1.1/8.8.8.8 failed! Local node will not serve as public exit.")

        swanctl_ips = get_swanctl_remote_ips()

        active_nodes = []
        for node in NODES:
            name = node["name"]
            dn42_ip = node.get("dn42Ip")
            if not dn42_ip:
                continue

            if name == LOCAL_HOSTNAME:
                if not local_wan_ok:
                    print(f"Skipping local node {name} from exit pool due to WAN failure")
                    continue
                rtt = 0.1
            else:
                rtt = ping_rtt(dn42_ip)

            if rtt is None:
                print(f"Node {name} ({dn42_ip}) unreachable via Babel")
                continue

            # Resolve public IP: prefer publicHost, fallback to active swanctl IKE SA remote IP
            public_host = node.get("publicHost")
            public_ip = resolve_ip(public_host) if public_host else None
            if not public_ip and name in swanctl_ips:
                public_ip = swanctl_ips[name]

            country, lat, lon = None, None, None
            if reader and public_ip:
                try:
                    rec = reader.get(public_ip)
                    if rec:
                        country = rec.get("country", {}).get("iso_code")
                        loc = rec.get("location", {})
                        lat = loc.get("latitude")
                        lon = loc.get("longitude")
                except Exception as e:
                    print(f"GeoIP failed for {name} ({public_ip}): {e}")

            # IATA 三字码纠偏与 Fallback 机制：防商家广播 IP 跨区漂移 (如香港广播 IP 归属 US)
            m_iata = re.match(r"^([a-z]{3})[0-9]+.*", name.lower())
            if m_iata:
                iata_code = m_iata.group(1)
                if iata_code in IATA_LOCATIONS:
                    ref = IATA_LOCATIONS[iata_code]
                    if not country or country != ref["country"]:
                        print(
                            f"IATA drift correction for {name}: {country} -> "
                            f"{ref['country']} ({ref['city']})"
                        )
                        country = ref["country"]
                        lat = ref["lat"]
                        lon = ref["lon"]
                    elif lat is None or lon is None:
                        lat = ref["lat"]
                        lon = ref["lon"]

            if not country or lat is None or lon is None:
                print(f"Warning: Could not determine location for node {name}, skipping from exit pool")
                continue

            active_nodes.append({
                "name": name,
                "dn42Ip": dn42_ip,
                "publicIp": public_ip or "unknown",
                "country": country,
                "lat": lat,
                "lon": lon,
                "internal_rtt": rtt,
            })
            print(f"Healthy exit candidate {name}: {country} ({lat:.2f}, {lon:.2f}), RTT={rtt:.1f}ms")

        os.makedirs(os.path.dirname(OUTPUT_CONF), exist_ok=True)
        if not active_nodes:
            print("No active nodes available! Writing empty route config.")
            with open(OUTPUT_CONF, "w") as f:
                f.write("# No active SDN nodes\n")
            subprocess.run(["birdc", "configure"], check=False)
            return

        node_by_ip = {n["dn42Ip"]: n["name"] for n in active_nodes}
        # Group subnets by best exit node
        node_assigned_nets = collections.defaultdict(list)

        # 遍历 COUNTRY_CIDR_DIR 下所有国家的 CIDR 文件（如 de.cidr, us.cidr 等）
        cidr_files = glob.glob(os.path.join(COUNTRY_CIDR_DIR, "*.cidr"))
        if not cidr_files:
            print(f"Notice: No .cidr files found in {COUNTRY_CIDR_DIR}. Waiting for sdn-sync-cidrs.")

        for cpath in sorted(cidr_files):
            c_code = os.path.basename(cpath).replace(".cidr", "").upper()
            # 跳过国内网段（由策略路由直通 eth0 出口）
            if c_code == "CN":
                continue

            same_country_nodes = [n for n in active_nodes if n["country"] == c_code]

            try:
                with open(cpath) as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        try:
                            net = ipaddress.ip_network(line)
                        except Exception:
                            continue

                        # 精确查询目标网段在 MMDB 中的具体坐标（实现同国多出口自动分流，如 sjc0 vs dfw0）
                        sub_lat, sub_lon = None, None
                        if reader:
                            try:
                                rec = reader.get(str(net.network_address))
                                if rec and "location" in rec:
                                    loc = rec["location"]
                                    sub_lat = loc.get("latitude")
                                    sub_lon = loc.get("longitude")
                            except Exception:
                                pass

                        # 选路决策：
                        if same_country_nodes:
                            # 本国已有在线节点：
                            if sub_lat is not None and sub_lon is not None and len(same_country_nodes) > 1:
                                best_node = min(
                                    same_country_nodes,
                                    key=lambda n: haversine_km(sub_lat, sub_lon, n["lat"], n["lon"]),
                                )
                            else:
                                best_node = min(same_country_nodes, key=lambda n: n["internal_rtt"])
                        else:
                            # 本国无在线节点（如加拿大 CA）：按距目标网段坐标球面距离折算延迟 + 内网 RTT 择优
                            if sub_lat is not None and sub_lon is not None:
                                best_node = min(
                                    active_nodes,
                                    key=lambda n: (haversine_km(sub_lat, sub_lon, n["lat"], n["lon"]) * 0.01) + n["internal_rtt"],
                                )
                            else:
                                best_node = min(active_nodes, key=lambda n: n["internal_rtt"])

                        node_assigned_nets[best_node["dn42Ip"]].append(net)
            except Exception as e:
                print(f"Error processing CIDR file {cpath}: {e}")

        # 超级聚合（Supernet Collapse）：将归属同一个出口节点的相邻网段合并，大幅降低内核 table 200 路由表条目
        gen_time = time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
        lines = [
            "# Auto-generated by SDN Country Arbiter",
            f"# Generated at {gen_time}",
            f"# Active cluster nodes: {len(active_nodes)}",
        ]
        for node in active_nodes:
            lines.append(f"# Node {node['name']} ({node['country']}) -> {node['dn42Ip']}")

        total_routes = 0
        for dn42_ip, nets in node_assigned_nets.items():
            collapsed = list(ipaddress.collapse_addresses(nets))
            exit_name = node_by_ip.get(dn42_ip, "exit")
            for cnet in collapsed:
                lines.append(f"route {cnet} recursive {dn42_ip}; # -> {exit_name}")
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
            print(f"Updated {OUTPUT_CONF} with {total_routes} collapsed routes.")
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

    enableAcceleration = mkOption {
      type = types.bool;
      default = dn42Data.mesh.${hostName}.acceleration or dn42Data.mesh.${hostName}.enableClient or false;
      description = "Whether this machine routes its own local outbound traffic through DN42 SDN table 200 for overseas acceleration (configured via terraform/dn42.tf, defaults to false)";
    };

    enableClient = mkOption {
      type = types.bool;
      default = cfg.enableAcceleration;
      description = "Deprecated alias for enableAcceleration";
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
    networking.iproute2 = mkIf isAccelerated {
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
          while ip rule del priority 8980 2>/dev/null; do :; done
          while ip rule del priority 9999 2>/dev/null; do :; done

          # ── Priority 79: 集群公网端点防死锁 ──
          # 强制将所有集群节点的公网 IP 解析到 main 表（走物理网卡原生出口），彻底杜绝底层通信误入 table 200
          ${lib.concatMapStringsSep "\n" (
            ip: "ip rule add to ${ip}/32 lookup main priority 79"
          ) allClusterPublicIps}

          # ── Priority 80-82: 底层加密隧道与协议防死锁 ──
          # 豁免 strongSwan (ESP / IKE UDP 4500, 500) 与外部 WireGuard 加密底包，强制查 main 表
          # 关键：同时对 udp 与 tcp (Mimic Fake-TCP) 双协议在 500 和 4500 端口进行对称豁免，
          # 防止 Mimic 发出的原生 TCP 握手/保活包穿透 priority 81 掉入 table 200 (SDN 加速) 或 table 2022 (Mihomo TUN) 导致握手死锁！
          ip rule add ipproto esp lookup main priority 80
          for proto in udp tcp; do
            for port in 500 4500; do
              ip rule add ipproto $proto sport $port lookup main priority 81
              ip rule add ipproto $proto dport $port lookup main priority 81
            done
          done
          ip rule add fwmark 51820 lookup main priority 82

          # ── Priority 90: DN42 内部网段双向直连与 ICMP 差错放行 ──
          # 访问 DN42 内部网段强制查 main 表（走 Babel / BGP 内部最优 IGP 路径）
          # 同时豁免源为 DN42 的出向报文（特别是 XFRM 接口 MTU 1360 产生的 ICMP Fragmentation Needed / Packet Too Big 报错），
          # 彻底杜绝 PMTUD 失败导致的 QUIC (HTTP/3 UDP 443) 网页加载无限转圈假死
          ip rule add to 172.20.0.0/14 lookup main priority 90
          ip rule add from 172.20.0.0/14 lookup main priority 90
          ip rule add to 10.0.0.0/8 lookup main priority 90
          ip rule add from 10.0.0.0/8 lookup main priority 90

          # ── Priority 8980: Mihomo DIRECT 流量出海分流 ──
          # 当 Mihomo 运行时，打有 fwmark 0x1 的 DIRECT 出站流量优先查 table 200 (sdn_accel)，
          # 使得 Mihomo 中配置为 DIRECT 的国外网站（如 PROXY 组选 DIRECT）通过 DN42 骨干网出海加速
          ${lib.optionalString isAccelerated ''
            ip rule add fwmark 0x1/0x1 lookup ${cfg.tableName} priority 8980
          ''}

          # ── Priority 9999: 无 Mihomo 时的原生全系统 DN42 兜底加速 ──
          # 当系统未开启 Mihomo（或流量未被 TUN 捕获）时，所有出站流量降级匹配 priority 9999，
          # 查 table 200 (sdn_accel) 直接通过 DN42 访问 Google 及全球互联网，实现无代理开箱即用
          ${lib.optionalString isAccelerated ''
            ip rule add lookup ${cfg.tableName} priority 9999
          ''}

          # IPv6 防环与策略路由
          while ip -6 rule del priority 79 2>/dev/null; do :; done
          while ip -6 rule del priority 80 2>/dev/null; do :; done
          while ip -6 rule del priority 81 2>/dev/null; do :; done
          while ip -6 rule del priority 82 2>/dev/null; do :; done
          while ip -6 rule del priority 90 2>/dev/null; do :; done
          while ip -6 rule del priority 100 2>/dev/null; do :; done
          while ip -6 rule del priority 8980 2>/dev/null; do :; done
          while ip -6 rule del priority 9999 2>/dev/null; do :; done

          ${lib.concatMapStringsSep "\n" (
            ip: "ip -6 rule add to ${ip}/128 lookup main priority 79"
          ) allClusterPublicV6s}

          ip -6 rule add ipproto esp lookup main priority 80
          for proto in udp tcp; do
            for port in 500 4500; do
              ip -6 rule add ipproto $proto sport $port lookup main priority 81
              ip -6 rule add ipproto $proto dport $port lookup main priority 81
            done
          done
          ip -6 rule add fwmark 51820 lookup main priority 82
          ip -6 rule add to fd00::/8 lookup main priority 90
          ip -6 rule add from fd00::/8 lookup main priority 90
          ip -6 rule add to fe80::/10 lookup main priority 90
          ip -6 rule add from fe80::/10 lookup main priority 90

          ${lib.optionalString isAccelerated ''
            ip -6 rule add fwmark 0x1/0x1 lookup ${cfg.tableName} priority 8980
            ip -6 rule add lookup ${cfg.tableName} priority 9999
          ''}
        '';
        ExecStop = pkgs.writeShellScript "sdn-policy-routing-stop" ''
          while ip rule del priority 79 2>/dev/null; do :; done
          while ip rule del priority 80 2>/dev/null; do :; done
          while ip rule del priority 81 2>/dev/null; do :; done
          while ip rule del priority 82 2>/dev/null; do :; done
          while ip rule del priority 90 2>/dev/null; do :; done
          while ip rule del priority 100 2>/dev/null; do :; done
          while ip rule del priority 8980 2>/dev/null; do :; done
          while ip rule del priority 9999 2>/dev/null; do :; done
          while ip -6 rule del priority 79 2>/dev/null; do :; done
          while ip -6 rule del priority 80 2>/dev/null; do :; done
          while ip -6 rule del priority 81 2>/dev/null; do :; done
          while ip -6 rule del priority 82 2>/dev/null; do :; done
          while ip -6 rule del priority 90 2>/dev/null; do :; done
          while ip -6 rule del priority 100 2>/dev/null; do :; done
          while ip -6 rule del priority 8980 2>/dev/null; do :; done
          while ip -6 rule del priority 9999 2>/dev/null; do :; done
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
        multihop {
          min rx interval 1000 ms;
          min tx interval 1000 ms;
          multiplier 5;
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

      ${lib.optionalString isAccelerated ''
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
        pkgs.strongswan
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
        for code in de us jp hk gb fr sg ca au kr nl tw se no fi dk ie it es pt pl at cz ru ua in my id th vn ph br mx ar cl za ae sa il tr nz ch be ro bg hu gr sk ee lv lt lu is cy mt; do
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
