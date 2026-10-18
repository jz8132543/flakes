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

  stripPort =
    str:
    if lib.hasPrefix "[" str then
      lib.head (lib.splitString "]" (lib.removePrefix "[" str))
    else if (lib.length (lib.splitString ":" str)) == 2 then
      lib.head (lib.splitString ":" str)
    else
      str;

  extractPort =
    str:
    if str == null || !lib.isString str then
      null
    else if lib.hasInfix "]:" str then
      let
        parts = lib.splitString "]:" str;
        p = if lib.length parts >= 2 then lib.toInt (lib.last parts) else null;
      in
      if p != null && p > 0 && p < 65536 then p else null
    else if !lib.hasInfix "[" str && (lib.length (lib.splitString ":" str)) == 2 then
      let
        parts = lib.splitString ":" str;
        p = lib.toInt (lib.last parts);
      in
      if p > 0 && p < 65536 then p else null
    else
      null;

  selfData = config.lib.self.data or (lib.importJSON ../../../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };

  meshNodeSubmodule = types.submodule (
    { name, config, ... }:
    let
      targetNode = if name == "thisNode" then hostName else name;
      nodeHostData = selfData.hosts.${targetNode} or { };
      nodeMeshCfg = dn42Data.mesh.${targetNode} or { };
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

      normalizedEndpoints =
        let
          edgeNode = lib.findFirst (n: n.name == targetNode) null (selfData.cdn.edgeNodes or [ ]);
          edgeEndpoints = lib.optionalAttrs (edgeNode != null) (
            lib.optionalAttrs (edgeNode ? ipv6 && edgeNode.ipv6 != null) { v6 = edgeNode.ipv6; }
            // lib.optionalAttrs (edgeNode ? ipv4 && edgeNode.ipv4 != null) { v4 = edgeNode.ipv4; }
          );
          rawEp =
            if nodeMeshCfg ? endpoints && nodeMeshCfg.endpoints != { } then
              nodeMeshCfg.endpoints
            else if edgeEndpoints != { } then
              edgeEndpoints
            else
              nodeMeshCfg.endpoint or "${targetNode}.dora.im:${toString (nodeMeshCfg.listenPort or 51821)}";
        in
        if rawEp == null then
          { }
        else if lib.isAttrs rawEp then
          lib.mapAttrs (_: stripPort) rawEp
        else if lib.isString rawEp && rawEp != "" then
          { default = stripPort rawEp; }
        else
          { };

      detectedPort =
        let
          rawEp =
            if nodeMeshCfg ? endpoints && nodeMeshCfg.endpoints != { } then
              nodeMeshCfg.endpoints
            else
              nodeMeshCfg.endpoint or null;
          rawList =
            if rawEp == null then
              [ ]
            else if lib.isString rawEp then
              [ rawEp ]
            else if lib.isAttrs rawEp then
              lib.attrValues rawEp
            else
              [ ];
          ports = lib.filter (p: p != null) (map extractPort rawList);
        in
        if ports != [ ] then lib.head ports else null;
    in
    {
      freeformType = types.attrsOf types.anything;

      options = {
        enable = mkOption {
          type = types.bool;
          default = nodeMeshCfg.enable or true;
          description = "Whether this node is enabled in the DN42 mesh";
        };

        id = mkOption {
          type = types.nullOr types.int;
          default = nodeMeshCfg.id or hIdx;
          description = "Unique node ID";
        };

        ike_port = mkOption {
          type = types.nullOr types.port;
          default = nodeMeshCfg.ike_port or null;
          description = "IKE port alias from Terraform";
        };

        nat_t_port = mkOption {
          type = types.nullOr types.port;
          default = nodeMeshCfg.nat_t_port or null;
          description = "NAT-T port alias from Terraform";
        };

        is_controller = mkOption {
          type = types.nullOr types.bool;
          default = nodeMeshCfg.is_controller or null;
          description = "SD-WAN controller flag from Terraform";
        };

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
          type = types.nullOr (types.either types.str (types.attrsOf types.str));
          default =
            nodeMeshCfg.endpoint or (normalizedEndpoints.default
              or (if normalizedEndpoints != { } then normalizedEndpoints else null)
            );
          description = "Public WireGuard / IPsec endpoint for this node, or null if behind NAT";
        };

        endpointV6 = mkOption {
          type = types.nullOr types.str;
          default =
            let
              edgeNode = lib.findFirst (n: n.name == name) null (selfData.cdn.edgeNodes or [ ]);
            in
            nodeMeshCfg.endpointV6 or (if edgeNode != null && edgeNode ? ipv6 then edgeNode.ipv6 else null);
          description = "Public IPv6 endpoint for this peer (preferred for IPsec when IPv4 is behind NAT)";
        };

        listenPort = mkOption {
          type = types.port;
          default = nodeMeshCfg.listenPort or 51821;
          description = "WireGuard listen port";
        };

        ikePort = mkOption {
          type = types.port;
          default =
            if config.ike_port != null then
              config.ike_port
            else
              nodeMeshCfg.ikePort or (nodeMeshCfg.ike_port or 500);
          description = "strongSwan charon.port for IKE (default 500)";
        };

        natTPort = mkOption {
          type = types.port;
          default =
            if config.nat_t_port != null then
              config.nat_t_port
            else
              nodeMeshCfg.natTPort or (nodeMeshCfg.nat_t_port or (nodeMeshCfg.port or (
                if detectedPort != null && detectedPort != (nodeMeshCfg.listenPort or 51821) then
                  detectedPort
                else
                  4500
              )
              )
              );
          description = "strongSwan charon.port_nat_t (ESP-in-UDP NAT-T / Mimic Fake-TCP port)";
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
          default = if config.id != null then config.id else (nodeMeshCfg.id or hIdx);
          description = "Host index of this node";
        };

        linkLocalIpv6 = mkOption {
          type = types.str;
          default = if hIdx != null then "fe80::${toString hIdx}/64" else "fe80::1/64";
          description = "Peer link-local IPv6 address";
        };

        endpoints = mkOption {
          type = types.attrsOf types.str;
          default = normalizedEndpoints;
          description = "All available public IP/domain endpoints for multi-path/dual-stack tunnels";
        };

        multipath = mkOption {
          type = types.bool;
          default =
            (cfg.thisNode.endpoint != null || (cfg.thisNode.endpoints or { }) != { })
            && (cfg.multipath.enable || (lib.elem name cfg.multipath.peers))
            && (lib.length (lib.attrNames config.endpoints) > 1);
          description = "Whether to establish concurrent tunnels for all endpoints of this peer";
        };

        persistentKeepalive = mkOption {
          type = types.nullOr types.int;
          default =
            if (cfg.thisNode.endpoint == null && (nodeMeshCfg.endpoint or null != null)) then 25 else null;
          description = "WireGuard persistentKeepalive in seconds (25s on NAT/client side, null on server)";
        };

        nat = mkOption {
          type = types.bool;
          default =
            nodeMeshCfg.nat or (
              (nodeMeshCfg.role or "internal") == "internal"
              || (nodeMeshCfg.endpoint or null == null && (nodeMeshCfg.endpoints or { }) == { })
            );
          description = "Whether this node is behind NAT (cannot accept inbound connections on IPv4, requiring passive responder on servers)";
        };

        acceleration = mkOption {
          type = types.bool;
          default = nodeMeshCfg.acceleration or nodeMeshCfg.enableClient or false;
          description = "Whether this node routes its outbound internet traffic via DN42 SDN table 200";
        };
      };
    }
  );

  # Exclude self and disabled nodes
  otherNodes = filterAttrs (n: p: n != hostName && (p.enable or true)) cfg.nodes;

  # Active mesh peers: a pairwise connection can be formed if at least one side has a public endpoint!
  activePeers = filterAttrs (
    _: peer:
    (cfg.thisNode.endpoint != null)
    || (cfg.thisNode.endpoints != { })
    || (peer.endpoint != null)
    || (peer.endpoints != { })
  ) otherNodes;

  # 隧道实例集合：将每个 activePeer 展开为一个或多个物理隧道实例

  selfNodeId = baseCfg.hostIndex;
  selfDn42Ip4 = lib.head (lib.splitString "/" baseCfg.nodeIpv4);
  selfDn42Ip6 = lib.head (lib.splitString "/" baseCfg.nodeIpv6);

  controllerUrls =
    let
      controllers = lib.filterAttrs (_: node: node.is_controller or false) (dn42Data.mesh or { });
    in
    if controllers != { } then
      lib.mapAttrsToList (
        name: _: "http://${name}.dora.im:${toString baseCfg.sdwan.controllerPort}"
      ) controllers
    else
      [ ];

  tokenFile =
    if cfg.ipsec.pskFile != null then
      cfg.ipsec.pskFile
    else
      pkgs.writeText "dn42-sdwan-token" cfg.ipsec.psk;

  bootstrapPeersFile = pkgs.writeText "bootstrap-peers.json" (
    builtins.toJSON (
      lib.mapAttrs (
        name: hData:
        let
          hIdx =
            if hData ? host_indices && hData.host_indices != [ ] then lib.head hData.host_indices else 99;
          v4 =
            if hData ? dn42_addresses_v4 && hData.dn42_addresses_v4 != [ ] then
              lib.head hData.dn42_addresses_v4
            else
              "172.20.232.${toString hIdx}";
          v6 =
            if hData ? dn42_addresses_v6 && hData.dn42_addresses_v6 != [ ] then
              lib.head hData.dn42_addresses_v6
            else
              "";
          edgeNode = lib.findFirst (n: n.name == name) null (selfData.cdn.edgeNodes or [ ]);
          meshNode = dn42Data.mesh.${name} or { };
          isNat = meshNode.nat or (meshNode.endpoints or { } == { });
          natTPort = meshNode.nat_t_port or (meshNode.natTPort or 4500);
          ikePort = meshNode.ike_port or (meshNode.ikePort or 500);

          nodeEndpoints =
            if meshNode ? endpoints && meshNode.endpoints != { } then
              meshNode.endpoints
            else if edgeNode != null then
              lib.optionalAttrs (edgeNode ? ipv4 && edgeNode.ipv4 != null) {
                v4 = "${edgeNode.ipv4}:${toString natTPort}";
              }
              // lib.optionalAttrs (edgeNode ? ipv6 && edgeNode.ipv6 != null) {
                v6 = "[${edgeNode.ipv6}]:${toString natTPort}";
              }
            else if !isNat then
              { default = "${name}.dora.im:${toString natTPort}"; }
            else
              { };

          pubIpv4 =
            if edgeNode != null && edgeNode ? ipv4 && edgeNode.ipv4 != null then
              edgeNode.ipv4
            else if !isNat then
              "${name}.dora.im"
            else
              "";
          pubIpv6 =
            if edgeNode != null && edgeNode ? ipv6 && edgeNode.ipv6 != null then
              edgeNode.ipv6
            else if !isNat then
              "${name}.dora.im"
            else
              "";
        in
        {
          id = hIdx;
          dn42_ip4 = v4;
          dn42_ip6 = v6;
          endpoints = nodeEndpoints;
          ipv4 = pubIpv4;
          ipv6 = pubIpv6;
          nat_t_port = natTPort;
          ike_port = ikePort;
          pubkey = "";
          updated_at = 0;
        }
      ) (selfData.hosts or { })
    )
  );

  # ── Mimic Fake-TCP 启动包装脚本 ($O(1) 本机真实 IP 动态自闭环) ──
  mimicStartScript = pkgs.writeShellScript "mimic-start-wrapper" ''
    set -euo pipefail
    IFACE="$1"

    # 1. 清理该网卡上残留的旧 BPF clsact qdisc、XDP 挂载与 /run/mimic 锁文件
    ${pkgs.iproute2}/bin/tc qdisc del dev "$IFACE" clsact 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link set dev "$IFACE" xdp off 2>/dev/null || true
    IFINDEX=$(${pkgs.iproute2}/bin/ip -o link show dev "$IFACE" 2>/dev/null | ${pkgs.gawk}/bin/awk -F': ' '{print $1}' || true)
    if [ -n "$IFINDEX" ]; then
      for lock in /run/mimic/*_"''${IFINDEX}".lock; do
        if [ -f "$lock" ]; then
          PID=$(${pkgs.gawk}/bin/awk -F'=' '$1=="pid"{print $2}' "$lock" 2>/dev/null || true)
          if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
            kill -15 "$PID" 2>/dev/null || true
            sleep 0.2
            kill -9 "$PID" 2>/dev/null || true
          fi
          rm -f "$lock" 2>/dev/null || true
        fi
      done
    fi

    # 2. 靶向关闭网卡 GRO/LRO 与硬件 Checksum Offload：
    #    - 关 gro/rx-gro-hw/lro：防止 skb-XDP 之前多个 Fake-TCP 包被合并破坏 12 字节尾部边界
    #    - 关 tx/rx offload：迫使内核在进入 Mimic (TC Egress) 前完成软件校验和计算，且接收端不丢弃包
    ${pkgs.ethtool}/bin/ethtool -K "$IFACE" gro off rx-gro-hw off lro off gso off tso off tx off rx off 2>/dev/null || true
    ${pkgs.ethtool}/bin/ethtool -K "$IFACE" tx-udp_tnl-segmentation off tx-udp_tnl-csum-segmentation off 2>/dev/null || true

    # 如果暂未获得 Global IP，短暂等待最多 5 秒
    for i in $(seq 1 5); do
      if [ -n "$(${pkgs.iproute2}/bin/ip -o addr show dev "$IFACE" scope global 2>/dev/null)" ]; then
        break
      fi
      sleep 1
    done

    # 3. 动态读取当前网卡 (%I) 上的真实 Global IPv4 与 IPv6 地址（绝不可用 0.0.0.0 或 [::]）
    FILTER_ARGS=()
    while read -r ip4; do
      [ -n "$ip4" ] && FILTER_ARGS+=("-f" "local=''${ip4}:${toString baseCfg.natTPort}" "-f" "local=''${ip4}:${toString baseCfg.ikePort}")
    done < <(${pkgs.iproute2}/bin/ip -4 -o addr show dev "$IFACE" scope global 2>/dev/null | ${pkgs.gawk}/bin/awk '{split($4,a,"/"); print a[1]}')

    while read -r ip6; do
      [ -n "$ip6" ] && FILTER_ARGS+=("-f" "local=[''${ip6}]:${toString baseCfg.natTPort}" "-f" "local=[''${ip6}]:${toString baseCfg.ikePort}")
    done < <(${pkgs.iproute2}/bin/ip -6 -o addr show dev "$IFACE" scope global 2>/dev/null | ${pkgs.gawk}/bin/awk '{split($4,a,"/"); print a[1]}')

    if [ ''${#FILTER_ARGS[@]} -eq 0 ]; then
      echo "No global IP on $IFACE yet, waiting..."
      exit 1
    fi

    echo "Starting mimic on $IFACE (xdp-mode=skb) with filters: ''${FILTER_ARGS[*]}"
    exec ${pkgs.mimic}/bin/mimic run "$IFACE" --xdp-mode skb "''${FILTER_ARGS[@]}"
  '';

  # ── SD-WAN Controller 轻量级 HTTP 同步处理脚本 ──
  sdwanControllerScript = pkgs.writeShellScript "dn42-sdwan-controller-handler" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          bash
          coreutils
          jq
          util-linux
        ]
      )
    }"
    REGISTRY_DIR="/var/lib/dn42-sdwan"
    REGISTRY_FILE="$REGISTRY_DIR/registry.json"
    mkdir -p "$REGISTRY_DIR"

    if [ ! -s "$REGISTRY_FILE" ]; then
      cp "${bootstrapPeersFile}" "$REGISTRY_FILE"
    else
      jq -s '
        (.[0] // {}) as $bootstrap | (.[1] // {}) as $cache |
        reduce ($bootstrap | to_entries[]) as $item ($cache;
          if (.[$item.key] == null) or ((.[$item.key].updated_at // 0) == 0)
          then .[$item.key] = $item.value else . end
        )
      ' "${bootstrapPeersFile}" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    fi

    read -r request_line || exit 0
    read -r method path proto <<< "$request_line"
    content_length=0
    auth_header=""

    while IFS= read -r line; do
      line=$(tr -d "\r" <<< "$line")
      [ -z "$line" ] && break
      lower_line=$(tr "[:upper:]" "[:lower:]" <<< "$line")
      if [[ "$lower_line" =~ ^content-length:[[:space:]]*([0-9]+) ]]; then
        content_length="''${BASH_REMATCH[1]}"
      elif [[ "$lower_line" =~ ^x-dn42-auth:[[:space:]]*(.*) ]]; then
        auth_header="''${BASH_REMATCH[1]}"
      fi
    done

    EXPECTED_AUTH=$(cat "${tokenFile}")
    if [ "$auth_header" != "$EXPECTED_AUTH" ]; then
      printf "HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\nUnauthorized\n"
      exit 0
    fi

    if [ "$method" = "POST" ] && [ "$content_length" -gt 0 ]; then
      body=$(head -c "$content_length")
      if echo "$body" | jq -e 'type == "object"' >/dev/null 2>&1; then
        (
          flock -x 200
          jq -s '
            (.[0] // {}) as $orig | (.[1] // {}) as $new |
            reduce ($new | to_entries[]) as $item ($orig;
              if (.[$item.key] == null) or (($item.value.updated_at // 0) >= (.[$item.key].updated_at // 0))
              then .[$item.key] = $item.value
              else . end
            )
          ' "$REGISTRY_FILE" <(echo "$body") > "$REGISTRY_FILE.tmp"
          mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
        ) 200>"$REGISTRY_DIR/registry.lock"
      fi
    fi

    resp=$(cat "$REGISTRY_FILE")
    len=$(printf "%s" "$resp" | wc -c)
    printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" "$len" "$resp"
  '';

  # ── 全节点 SD-WAN Agent 同步维护脚本 ──
  sdwanAgentScript = pkgs.writeShellScript "dn42-sdwan-agent" ''
        set -euo pipefail
        export PATH="${
          lib.makeBinPath (
            with pkgs;
            [
              bash
              coreutils
              jq
              curl
              iproute2
              ethtool
              strongswan
              gawk
              gnugrep
              findutils
            ]
          )
        }"

        STATE_DIR="/var/lib/dn42-sdwan"
        CACHE_FILE="$STATE_DIR/peers.json"
        SWAN_D="/run/swanctl/conf.d"
        mkdir -p "$STATE_DIR" "$SWAN_D"

        # 辅助函数：从 host:port 字符串中分离 host 与 port (支持 IPv6 [addr]:port 语法)
        extract_host_port() {
          local raw="$1"
          local def_port="$2"
          if [[ "$raw" =~ ^\[(.*)\]:([0-9]+)$ ]]; then
            echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]}"
          elif [[ "$raw" =~ ^\[(.*)\]$ ]]; then
            echo "''${BASH_REMATCH[1]} $def_port"
          elif [[ "$raw" =~ ^([^:]+):([0-9]+)$ ]]; then
            echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]}"
          else
            echo "$raw $def_port"
          fi
        }

        # 1. 若本地缓存不存在，用 bootstrapPeersFile 初始化；若存在，用 bootstrap 刷新 updated_at == 0 的静态配置
        if [ ! -s "$CACHE_FILE" ]; then
          cp "${bootstrapPeersFile}" "$CACHE_FILE"
        else
          jq -s '
            (.[0] // {}) as $bootstrap | (.[1] // {}) as $cache |
            reduce ($bootstrap | to_entries[]) as $item ($cache;
              if (.[$item.key] == null) or ((.[$item.key].updated_at // 0) == 0)
              then .[$item.key] = $item.value else . end
            )
          ' "${bootstrapPeersFile}" "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        fi

        SELF_NAME="${hostName}"
        SELF_ID="${toString selfNodeId}"
        SELF_IP4="${selfDn42Ip4}"
        SELF_IP6="${selfDn42Ip6}"
        SELF_PORT="${toString baseCfg.natTPort}"
        SELF_IKE_PORT="${toString baseCfg.ikePort}"
        CONTROLLERS=(${lib.concatStringsSep " " controllerUrls})

        # 2a. 本地网卡自探测 (参考 Tailscale netmon / RFC1918 过滤规范)
        DISCOVERED_IPS=$(ip -j addr show up 2>/dev/null | jq '
          [ .[]? |
            select(.ifname | test("^(lo|docker.*|podman.*|veth.*|br-.*|dn42.*|tailscale.*|meta.*|dummy.*|xfrm.*|wireguard.*|wg.*)$") | not) |
            .ifname as $ifname |
            .addr_info[]? |
            select(.scope == "global") |
            {
              ifname: $ifname,
              family: .family,
              local: .local,
              is_private: (
                if .family == "inet" then
                  (.local | (
                    startswith("10.") or
                    startswith("192.168.") or
                    startswith("100.") or
                    startswith("172.16.") or startswith("172.17.") or startswith("172.18.") or startswith("172.19.") or
                    startswith("172.20.") or startswith("172.21.") or startswith("172.22.") or startswith("172.23.") or
                    startswith("172.24.") or startswith("172.25.") or startswith("172.26.") or startswith("172.27.") or
                    startswith("172.28.") or startswith("172.29.") or startswith("172.30.") or startswith("172.31.") or
                    startswith("127.") or
                    startswith("169.254.")
                  ))
                elif .family == "inet6" then
                  (.local | (
                    startswith("fe80:") or
                    startswith("fd") or
                    startswith("fc") or
                    . == "::1"
                  ))
                else false end
              )
            }
          ]
        ' 2>/dev/null || echo "[]")

        PUBLIC_V4=$(echo "$DISCOVERED_IPS" | jq -r '[.[] | select(.family == "inet" and .is_private == false).local][0] // empty')
        PUBLIC_V6=$(echo "$DISCOVERED_IPS" | jq -r '[.[] | select(.family == "inet6" and .is_private == false).local][0] // empty')

        # 2b. 提取或自适应扩充本机端点表
        STATIC_ENDPOINTS=$(jq -c --arg s "$SELF_NAME" '.[$s].endpoints // {}' "$CACHE_FILE" 2>/dev/null || echo "{}")
        SELF_ENDPOINTS="$STATIC_ENDPOINTS"
        if [ "$SELF_ENDPOINTS" = "{}" ] || [ -z "$SELF_ENDPOINTS" ]; then
          NEW_EPS="{}"
          if [ -n "$PUBLIC_V4" ]; then
            NEW_EPS=$(echo "$NEW_EPS" | jq --arg v4 "$PUBLIC_V4:$SELF_PORT" '. + { "auto_v4": $v4 }')
          fi
          if [ -n "$PUBLIC_V6" ]; then
            NEW_EPS=$(echo "$NEW_EPS" | jq --arg v6 "[$PUBLIC_V6]:$SELF_PORT" '. + { "auto_v6": $v6 }')
          fi
          if [ "$NEW_EPS" != "{}" ]; then
            SELF_ENDPOINTS="$NEW_EPS"
          fi
        fi

        # 2c. 向 3 台主控上报本机状态，并拉取最新全网节点表合并到本地缓存
        NOW=$(date +%s)
        SELF_PAYLOAD=$(jq -n \
          --arg name "$SELF_NAME" \
          --argjson id "$SELF_ID" \
          --arg dn42_ip4 "$SELF_IP4" \
          --arg dn42_ip6 "$SELF_IP6" \
          --argjson endpoints "$SELF_ENDPOINTS" \
          --argjson nat_t_port "$SELF_PORT" \
          --argjson ike_port "$SELF_IKE_PORT" \
          --arg pubkey "" \
          --argjson updated_at "$NOW" \
          '{($name): {id: $id, dn42_ip4: $dn42_ip4, dn42_ip6: $dn42_ip6, endpoints: $endpoints, nat_t_port: $nat_t_port, ike_port: $ike_port, pubkey: $pubkey, updated_at: $updated_at}}')

        TOKEN=$(cat "${tokenFile}")

        for ctrl in "''${CONTROLLERS[@]}"; do
          REMOTE_JSON=$(curl -fsSL --max-time 4 -X POST -H "X-DN42-Auth: $TOKEN" -d "$SELF_PAYLOAD" "$ctrl/sync" 2>/dev/null || true)
          if [ -n "$REMOTE_JSON" ] && echo "$REMOTE_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
            jq -s '
              (.[0] // {}) as $orig | (.[1] // {}) as $new |
              reduce ($new | to_entries[]) as $item ($orig;
                if (.[$item.key] == null) or (($item.value.updated_at // 0) >= (.[$item.key].updated_at // 0))
                then .[$item.key] = $item.value else . end
              )
            ' "$CACHE_FILE" <(echo "$REMOTE_JSON") > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
          fi
        done

        # 若本机是 Controller，将最新 peers.json 同步到 registry.json
        if [ "${if baseCfg.sdwan.isController then "1" else "0"}" = "1" ]; then
          cp "$CACHE_FILE" "$STATE_DIR/registry.json" 2>/dev/null || true
        fi

        # 3. 遍历 peers.json，热创建/维护多线路虚拟网卡 dn42x-* 与 swanctl 配置文件
        CONF_CHANGED=0
        HOSTS_TMP="/run/dn42-hosts.tmp"
        : > "$HOSTS_TMP"
        ACTIVE_CONF_FILES=()
        ALL_TUNNEL_INSTANCES=()
        ACTIVE_IFACES=()

        MY_EPS=$(jq -c --arg s "$SELF_NAME" '.[$s].endpoints // {}' "$CACHE_FILE" 2>/dev/null || echo "{}")
        MY_EPS_COUNT=$(echo "$MY_EPS" | jq 'keys | length' 2>/dev/null || echo "0")

        for peer in $(jq -r 'keys[]' "$CACHE_FILE"); do
          PEER_IP4=$(jq -r --arg p "$peer" '.[$p].dn42_ip4 // empty' "$CACHE_FILE")
          PEER_IP6=$(jq -r --arg p "$peer" '.[$p].dn42_ip6 // empty' "$CACHE_FILE")
          [ -z "$PEER_IP4" ] && continue
          echo "$PEER_IP4 ''${peer}.dn42" >> "$HOSTS_TMP"

          [ "$peer" = "$SELF_NAME" ] && continue

          PEER_ID=$(jq -r --arg p "$peer" '.[$p].id // empty' "$CACHE_FILE")
          [ -z "$PEER_ID" ] && continue

          PEER_EPS=$(jq -c --arg p "$peer" '.[$p].endpoints // {}' "$CACHE_FILE" 2>/dev/null || echo "{}")
          PEER_EPS_COUNT=$(echo "$PEER_EPS" | jq 'keys | length' 2>/dev/null || echo "0")
          PEER_PORT=$(jq -r --arg p "$peer" '.[$p].nat_t_port // 4500' "$CACHE_FILE")
          [ -z "$PEER_PORT" ] && PEER_PORT=4500

          if [ "$PEER_EPS_COUNT" -gt 1 ]; then
            # Case A: 对端定义了多条公网线路端点 (如 cu 的 4 端点)
            k_idx=0
            for ep_name in $(echo "$PEER_EPS" | jq -r 'keys[]'); do
              ep_raw=$(echo "$PEER_EPS" | jq -r --arg k "$ep_name" '.[$k]')
              read -r ep_host ep_port <<< "$(extract_host_port "$ep_raw" "$PEER_PORT")"
              if_id=$(( 1000 * k_idx + PEER_ID ))

              iface="dn42x-''${peer}-''${ep_name}"
              if [ ''${#iface} -gt 15 ]; then
                iface="dn42x-''${peer:0:5}-''${ep_name:0:3}"
              fi
              conn_name="dn42-''${peer}-''${ep_name}"
              local_addrs="%any"
              remote_addrs="''${ep_host}"
              start_action="start"
              dpd_action="restart"

              ALL_TUNNEL_INSTANCES+=("$iface;$if_id;$conn_name;$local_addrs;$remote_addrs;$ep_port;$start_action;$dpd_action;$PEER_IP4;$PEER_IP6;$peer")
              ACTIVE_IFACES+=("$iface")
              ACTIVE_CONF_FILES+=("sdwan-''${conn_name}.conf")
              k_idx=$(( k_idx + 1 ))
            done

          elif [ "$MY_EPS_COUNT" -gt 1 ] && [ "$PEER_EPS_COUNT" -le 1 ]; then
            # Case B: 本机有多条线路端点 (如在 cu 上运行)，对端为单端点或 NAT 节点
            k_idx=0
            peer_raw=$(echo "$PEER_EPS" | jq -r 'to_entries[0].value // empty')
            if [ -n "$peer_raw" ]; then
              read -r peer_host peer_p <<< "$(extract_host_port "$peer_raw" "$PEER_PORT")"
              remote_addrs="''${peer_host}"
              start_action="start"
              dpd_action="restart"
            else
              remote_addrs="%any"
              peer_p="$PEER_PORT"
              start_action="none"
              dpd_action="clear"
            fi

            for my_name in $(echo "$MY_EPS" | jq -r 'keys[]'); do
              my_raw=$(echo "$MY_EPS" | jq -r --arg k "$my_name" '.[$k]')
              read -r my_host my_p <<< "$(extract_host_port "$my_raw" "$SELF_PORT")"
              if_id=$(( 1000 * k_idx + PEER_ID ))

              iface="dn42x-''${peer}-''${my_name}"
              if [ ''${#iface} -gt 15 ]; then
                iface="dn42x-''${peer:0:5}-''${my_name:0:3}"
              fi
              conn_name="dn42-''${peer}-''${my_name}"
              local_addrs="''${my_host}"

              ALL_TUNNEL_INSTANCES+=("$iface;$if_id;$conn_name;$local_addrs;$remote_addrs;$peer_p;$start_action;$dpd_action;$PEER_IP4;$PEER_IP6;$peer")
              ACTIVE_IFACES+=("$iface")
              ACTIVE_CONF_FILES+=("sdwan-''${conn_name}.conf")
              k_idx=$(( k_idx + 1 ))
            done

          else
            # Case C: 常规单端点或纯 NAT 节点 (如 fra0 <-> sjc0, surface <-> fra0)
            if_id="$PEER_ID"
            iface="dn42x-''${peer}"
            conn_name="dn42-''${peer}"
            local_addrs="%any"

            peer_raw=$(echo "$PEER_EPS" | jq -r 'to_entries[0].value // empty')
            if [ -n "$peer_raw" ]; then
              read -r peer_host peer_p <<< "$(extract_host_port "$peer_raw" "$PEER_PORT")"
              remote_addrs="''${peer_host}"
              start_action="start"
              dpd_action="restart"
            else
              remote_addrs="%any"
              peer_p="$PEER_PORT"
              start_action="none"
              dpd_action="clear"
            fi

            ALL_TUNNEL_INSTANCES+=("$iface;$if_id;$conn_name;$local_addrs;$remote_addrs;$peer_p;$start_action;$dpd_action;$PEER_IP4;$PEER_IP6;$peer")
            ACTIVE_IFACES+=("$iface")
            ACTIVE_CONF_FILES+=("sdwan-''${conn_name}.conf")
          fi
        done

        # 3a. 清理已废弃的旧 dn42x-* 虚拟网卡（防止节点端点重命名/扩充时发生 if_id 冲突 EEXIST）
        for existing_iface in $(ip -o link show type xfrm 2>/dev/null | awk -F': ' '{print $2}' | awk -F'@' '{print $1}'); do
          [[ "$existing_iface" =~ ^dn42x- ]] || continue
          if ! [[ " ''${ACTIVE_IFACES[*]} " =~ " ''${existing_iface} " ]]; then
            ip link del "$existing_iface" 2>/dev/null || true
          fi
        done

        # 3b. 清理已废弃的旧 sdwan-*.conf 配置文件
        for existing_conf in "$SWAN_D"/sdwan-*.conf; do
          [ -e "$existing_conf" ] || continue
          base_name=$(basename "$existing_conf")
          if ! [[ " ''${ACTIVE_CONF_FILES[*]} " =~ " ''${base_name} " ]]; then
            rm -f "$existing_conf"
            CONF_CHANGED=1
          fi
        done

        # 3c. 实例化所有隧道：XFRM 设备与 swanctl 配置
        for inst in "''${ALL_TUNNEL_INSTANCES[@]}"; do
          IFS=';' read -r t_iface t_if_id t_conn t_laddrs t_raddrs t_rport t_saction t_dpd t_peer_ip4 t_peer_ip6 t_peer <<< "$inst"

          if ! ip link show "$t_iface" >/dev/null 2>&1; then
            # 彻底杜绝内核 EEXIST：若有残留旧网卡占用了该 if_id，先行清除
            old_dev=$(ip -d link show type xfrm 2>/dev/null | awk -v id="if_id 0x$(printf '%x' "$t_if_id")" '
              /^[0-9]+: dn42x-/ { iface=$2; sub(/:.*/,"",iface); sub(/@.*/,"",iface) }
              $0 ~ id { print iface }
            ' || true)
            if [ -n "$old_dev" ] && [ "$old_dev" != "$t_iface" ]; then
              ip link del "$old_dev" 2>/dev/null || true
            fi
            ip link add "$t_iface" type xfrm dev lo if_id "$t_if_id" 2>/dev/null || true
          fi
          ip link set "$t_iface" mtu 1360 multicast on up 2>/dev/null || true
          ethtool -K "$t_iface" tx off gso off gro off 2>/dev/null || true

          ip -4 addr replace "''${SELF_IP4}/32" peer "''${t_peer_ip4}/32" dev "$t_iface" 2>/dev/null || ip -4 addr replace "''${SELF_IP4}/32" dev "$t_iface" 2>/dev/null || true
          ip -6 addr replace "fe80::''${SELF_ID}/64" dev "$t_iface" 2>/dev/null || true
          [ -n "$SELF_IP6" ] && ip -6 addr replace "''${SELF_IP6}/128" dev "$t_iface" 2>/dev/null || true
          [ -n "''${t_peer_ip6}" ] && ip -6 route replace "''${t_peer_ip6}/128" dev "$t_iface" 2>/dev/null || true

          peer_conf="$SWAN_D/sdwan-''${t_conn}.conf"

          new_content=$(cat <<EOF
    connections {
      ''${t_conn} {
        version = 2
        mobike = no
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        dpd_timeout = 120s
        local_port = ''${SELF_PORT}
        remote_port = ''${t_rport}
        local_addrs = ''${t_laddrs}
        remote_addrs = ''${t_raddrs}

        proposals = aes256gcm128-sha256-x25519, chacha20poly1305-sha256-x25519, aes128gcm128-sha256-x25519

        local {
          auth = psk
          id = ''${SELF_NAME}.dn42
        }
        remote {
          auth = psk
          id = ''${t_peer}.dn42
        }
        children {
          ''${t_conn} {
            esp_proposals = aes256gcm128-x25519, chacha20poly1305-x25519, aes128gcm128-x25519
            local_ts = 172.20.0.0/14, 10.0.0.0/8, fd00::/8, fe80::/10, ff00::/8, 224.0.0.0/4
            remote_ts = 172.20.0.0/14, 10.0.0.0/8, fd00::/8, fe80::/10, ff00::/8, 224.0.0.0/4
            if_id_in = ''${t_if_id}
            if_id_out = ''${t_if_id}
            set_mark_out = 0x1
            mode = tunnel
            start_action = ''${t_saction}
            dpd_action = ''${t_dpd}
          }
        }
      }
    }
    EOF
    )

          if [ ! -f "$peer_conf" ] || [ "$new_content" != "$(cat "$peer_conf" 2>/dev/null || true)" ]; then
            echo "$new_content" > "$peer_conf"
            CONF_CHANGED=1
          fi
        done

        mv "$HOSTS_TMP" /run/dn42-hosts

        # 4. 仅在配置真正发生变化时增量热重载 strongSwan 与 BIRD，不中断已有连接
        if [ "$CONF_CHANGED" -eq 1 ]; then
          swanctl --load-all --noprompt 2>/dev/null || true
          birdc configure 2>/dev/null || true
          # 针对主动发起的隧道，重新触发一次握手确保新 Child SA TS 立即生效
          for inst in "''${ALL_TUNNEL_INSTANCES[@]}"; do
            IFS=';' read -r _ _ t_conn _ _ _ t_saction _ _ _ _ <<< "$inst"
            if [ "$t_saction" = "start" ]; then
              swanctl --initiate --child "$t_conn" 2>/dev/null || true
            fi
          done
        fi
  '';

in
{
  imports = [
    ./base.nix
  ];

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
        default = 1360;
        description = "MTU for XFRM interfaces (lowered to 1360 to accommodate Mimic Fake-TCP header and UDP encapsulation overhead)";
      };

      forceUdpEncap = mkOption {
        type = types.bool;
        default = true;
        description = "Force UDP encapsulation for ESP (NAT-T on port 4500) to ensure 100% interception by Mimic into Fake-TCP";
      };

      ikePort = mkOption {
        type = types.port;
        default = baseCfg.ikePort;
        description = "strongSwan charon.port for IKE (default baseCfg.ikePort)";
      };

      port = mkOption {
        type = types.port;
        default = baseCfg.natTPort;
        description = "Standard strongSwan NAT-T UDP port for cluster mesh (ESP-in-UDP NAT-T / Mimic Fake-TCP)";
      };

      natTPort = mkOption {
        type = types.port;
        default = cfg.ipsec.port;
        description = "Alias for cfg.ipsec.port (ESP-in-UDP NAT-T / Mimic Fake-TCP port)";
      };

      clientPort = mkOption {
        type = types.port;
        default = cfg.ipsec.natTPort;
        description = "NAT client NAT-T port (defaults to cfg.ipsec.natTPort)";
      };

      mimic = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Mimic eBPF UDP-4500 to Fake-TCP-4500 obfuscation for IPsec mesh tunnel";
        };

        interfaces = mkOption {
          type = types.listOf types.str;
          default =
            let
              configuredInterfaces = builtins.filter (
                i: !lib.hasPrefix "dn42" i && !lib.hasPrefix "tailscale" i && !lib.hasPrefix "virbr" i && i != "lo"
              ) (builtins.attrNames (config.networking.interfaces or { }));
            in
            if configuredInterfaces != [ ] then configuredInterfaces else [ "eth0" ];
          description = "Physical network interfaces to attach Mimic on fixed server nodes";
        };

        xdpMode = mkOption {
          type = types.enum [
            "auto"
            "native"
            "skb"
          ];
          default = "skb";
          description = "Force XDP mode ('auto', 'native', 'skb'). Generic SKB mode runs reliably across all virtio_net and physical NICs.";
        };

        peers = mkOption {
          type = types.listOf types.str;
          default = builtins.attrNames (
            filterAttrs (
              _: p: (p.endpoint != null && p.endpoint != { }) || (p.endpoints or { } != { })
            ) otherNodes
          );
          description = "List of peer node names to obfuscate with Fake-TCP. Defaults generically to all mesh peers with reachable endpoints.";
        };

        allPeers = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to obfuscate all mesh peers with Fake-TCP (requires all nodes to run Mimic simultaneously)";
        };

        allTraffic = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to match local=0.0.0.0:4500 / local=[::]:4500 (transparently processing all inbound and outbound traffic on IPsec ports 4500 and 500 without per-peer whitelists)";
        };

        extraFilters = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Extra filter arguments to pass to mimic run (e.g. ['remote=x.x.x.x:4500'])";
        };
      };
    };

    multipath = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Globally enable multi-path dual-stack concurrent tunnels for mesh nodes with multiple endpoints";
      };

      peers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of peer names to enable concurrent multi-path tunnels for";
      };
    };

    allClusterTunnelPorts = mkOption {
      type = types.listOf types.port;
      internal = true;
      readOnly = true;
      default = lib.unique (
        [
          500
          4500
          cfg.ipsec.ikePort
          cfg.ipsec.natTPort
        ]
        ++ (lib.concatMap (n: [
          n.ikePort
          n.natTPort
        ]) (lib.attrValues cfg.nodes))
        ++ (lib.concatMap (
          n:
          let
            rawEp = n.endpoints or { };
            rawList = if lib.isAttrs rawEp then lib.attrValues rawEp else [ ];
            rawEpSingle = if n.endpoint != null && lib.isString n.endpoint then [ n.endpoint ] else [ ];
          in
          lib.filter (p: p != null && p != (n.listenPort or 51821) && p != 51820) (
            map extractPort (rawList ++ rawEpSingle)
          )
        ) (lib.attrValues cfg.nodes))
      );
      description = "All IKE and NAT-T ports used across the DN42 mesh cluster";
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
        ikePort = cfg.ipsec.ikePort;
        natTPort = cfg.ipsec.natTPort;
      };
      description = "Local node mesh attributes";
    };

    babel = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Babel IGP on mesh interfaces";
      };

      type = mkOption {
        type = types.enum [
          "wireless"
          "tunnel"
          "wired"
        ];
        default = "wireless";
        description = "Babel interface type ('wireless' activates ETX packet loss calculation)";
      };

      rxCost = mkOption {
        type = types.int;
        default = 256;
        description = "Babel rx cost for interface";
      };

      helloInterval = mkOption {
        type = types.int;
        default = 2;
        description = "Babel hello interval (seconds)";
      };

      updateInterval = mkOption {
        type = types.int;
        default = 8;
        description = "Babel update interval (seconds)";
      };

      rttMetric = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Babel RTT-based metric (real-time latency + loss routing)";
      };

      rttCost = mkOption {
        type = types.int;
        default = 512;
        description = "Babel RTT cost penalty added at rttMax";
      };

      rttMin = mkOption {
        type = types.int;
        default = 10;
        description = "Babel RTT min (ms)";
      };

      rttMax = mkOption {
        type = types.int;
        default = 300;
        description = "Babel RTT max (ms)";
      };

      rttDecay = mkOption {
        type = types.int;
        default = 84;
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
      assertions = [
        {
          assertion = cfg.backend != "ipsec" || baseCfg.ikePort != baseCfg.natTPort;
          message = "services.dn42: ikePort (${toString baseCfg.ikePort}) and natTPort (${toString baseCfg.natTPort}) must be different ports to avoid strongSwan charon socket collision.";
        }
      ]
      ++ lib.optionals (cfg.backend == "wireguard") (
        mapAttrsToList (peerName: peerCfg: {
          assertion = peerCfg.publicKey != null;
          message = "services.dn42.mesh: WireGuard public key for peer '${peerName}' is missing. Configure 'hosts.${peerName}.dn42_public_key' in lib/data/data.json.";
        }) activePeers
      );
    }

    # ── 2. IPsec / IKEv2 + XFRM 后端实现 ──────────────────────────────
    (mkIf (cfg.backend == "ipsec") (
      let
        portsCsv = concatStringsSep ", " (map toString cfg.allClusterTunnelPorts);
      in
      {
        boot.kernelModules = [
          "xfrm_interface"
          "esp4"
          "esp6"
        ];

        environment.systemPackages = [
          pkgs.strongswan
        ];

        # XFRM 虚拟网络网卡管理、SD-WAN Agent 与 Mimic Fake-TCP 守护服务
        systemd.services = {
          "dn42-sdwan-agent" = {
            description = "DN42 Multi-Master SD-WAN Tunnel Agent";
            after = [ "network.target" ];
            wants = [ "network.target" ];
            before = [
              "strongswan-swanctl.service"
              "bird.service"
            ];
            wantedBy = [ "multi-user.target" ];
            restartTriggers = [ sdwanAgentScript ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = false;
              ExecStart = "${sdwanAgentScript}";
            };
          };

          strongswan-swanctl = {
            after = [
              "network-online.target"
              "dn42-sdwan-agent.service"
            ]
            ++ lib.optional cfg.ipsec.mimic.enable "dn42-mimic-autobind.service";
            wants = [
              "network-online.target"
              "dn42-sdwan-agent.service"
            ]
            ++ lib.optional cfg.ipsec.mimic.enable "dn42-mimic-autobind.service";
            preStart = "mkdir -p /run/swanctl/conf.d";
          };
        }
        // (optionalAttrs (baseCfg.sdwan.enable && baseCfg.sdwan.isController) {
          "dn42-sdwan-controller" = {
            description = "DN42 Multi-Master SD-WAN Controller Service";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            restartTriggers = [ sdwanControllerScript ];
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "3s";
              ExecStart = "${pkgs.socat}/bin/socat -d -d TCP6-LISTEN:${toString baseCfg.sdwan.controllerPort},reuseaddr,fork,ipv6only=0 SYSTEM:\"${sdwanControllerScript}\"";
            };
          };
        })
        // (optionalAttrs cfg.ipsec.mimic.enable {
          "mimic@" = {
            description = "Mimic eBPF UDP/TCP tunnel obfuscation on %I";
            after = [
              "network-online.target"
              "sys-subsystem-net-devices-%i.device"
            ];
            wants = [ "network-online.target" ];
            bindsTo = [ "sys-subsystem-net-devices-%i.device" ];
            path = with pkgs; [
              iproute2
              ethtool
              kmod
              coreutils
              gawk
            ];
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "3s";
              ExecStart = "${mimicStartScript} %I";
              ExecStopPost = "${pkgs.writeShellScript "mimic-stop-post" ''
                set -u
                IFACE="$1"
                ${pkgs.iproute2}/bin/tc qdisc del dev "$IFACE" clsact 2>/dev/null || true
                ${pkgs.iproute2}/bin/ip link set dev "$IFACE" xdp off 2>/dev/null || true
                IFINDEX=$(${pkgs.iproute2}/bin/ip -o link show dev "$IFACE" 2>/dev/null | ${pkgs.gawk}/bin/awk -F': ' '{print $1}' || true)
                if [ -n "$IFINDEX" ]; then
                  rm -f /run/mimic/*_"''${IFINDEX}".lock 2>/dev/null || true
                fi
              ''} %I";
            };
          };

          "dn42-mimic-autobind" = {
            description = "Automatically bind Mimic to current default physical interface";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            before = [ "strongswan-swanctl.service" ];
            wantedBy = [ "multi-user.target" ];
            path = with pkgs; [
              iproute2
              systemd
              coreutils
              gawk
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "dn42-mimic-autobind" ''
                set -eu
                # 获取系统默认路由出口网卡 (如 wlp1s0 / wlan0 / eth0)
                IFACE=$(ip -4 route show default 2>/dev/null | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)
                if [ -z "$IFACE" ]; then
                  IFACE=$(ip -6 route show default 2>/dev/null | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)
                fi
                if [ -n "$IFACE" ] && [ "$IFACE" != "lo" ] && [[ ! "$IFACE" =~ ^(dn42|xfrm|tailscale|mihomo|Meta|meta|tun|veth|docker|virbr|br-|podman) ]]; then
                  echo "Auto-binding Mimic on default route interface: $IFACE"
                  systemctl start "mimic@$IFACE.service" || true
                fi
              '';
            };
          };
        });

        systemd.timers.dn42-sdwan-agent = {
          description = "DN42 Multi-Master SD-WAN Agent Sync Timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5s";
            OnUnitInactiveSec = "45s";
            AccuracySec = "5s";
          };
        };

        # 针对固定服务器节点（未启用 NetworkManager），开机自动启动物理出口网卡上的 mimic 服务实例
        systemd.targets.multi-user.wants = mkIf (
          cfg.ipsec.mimic.enable && !config.networking.networkmanager.enable
        ) (map (iface: "mimic@${iface}.service") cfg.ipsec.mimic.interfaces);

        # 若系统启用了 systemd-networkd，设置该接口为 Unmanaged 防止被 networkd 重置
        systemd.network.networks = mkIf config.systemd.network.enable {
          "70-dn42x" = {
            matchConfig.Name = "dn42x-*";
            linkConfig.Unmanaged = true;
          };
        };

        # Strongswan Swanctl 守护进程配置
        services.strongswan-swanctl = {
          enable = true;
          # 优化说明：
          # 1. threads: 采用 StrongSwan 官方默认线程池 (16 线程)，常驻物理内存仅 ~5.6MB，避免极限低线程导致 VICI IPC 死锁
          # 2. install_routes = no: 禁用 strongswan 自带路由安装，由 Bird 2 全权接管选路
          # 3. install_virtual_ip = no: 禁用虚拟 IP 分配，无状态消耗
          strongswan.extraConfig = ''
            charon {
              port = ${toString baseCfg.ikePort}
              port_nat_t = ${toString baseCfg.natTPort}
              fragment_size = 1240
              keep_alive = 10s
              # 放宽重传窗口与超时，容忍 Fake-TCP 遭遇运营商 RST 重握手，避免引发 BGP/Babel 路由震荡
              retransmit_tries = 8
              retransmit_timeout = 2.0
              retransmit_base = 1.2
              install_routes = no
              install_virtual_ip = no
              routing_table = 0
              routing_table_prio = 0
              cisco_unity = no
              send_vendor_id = no
              # 允许同一节点建立多个并发隧道（如多路径 IPv4 + IPv6 双栈并发，不因同名 ID 相互剔除）
              uniqueids = no
              interfaces_ignore = Meta, virbr*, tailscale*, easytier*, dn42*
              # 借鉴 linyinfeng/dotfiles: 忽略全局代理路由表 (2022)，迫使 charon 查询 main 表走物理网卡默认网关
              ignore_routing_tables = 2022
              plugins {
                socket-default {
                  # 设置 socket fwmark 为 0x1，使 IKE 与 NAT-T 流量原生匹配策略路由 lookup main，免于被代理 TUN 劫持
                  fwmark = 0x1
                }
              }
            }
          '';

          swanctl = {
            secrets.ike = mkIf (cfg.ipsec.pskFile == null) {
              mesh = {
                secret = cfg.ipsec.psk;
              };
            };
          };

          includes = [
            "/run/swanctl/conf.d/*.conf"
          ]
          ++ optional (cfg.ipsec.pskFile != null) cfg.ipsec.pskFile;
        };

        # MSS 钳制：防止内层经过 table 200 加速或 DN42 路由的 TCP 连接因外层多重封装 (XFRM + UDP) 超出 MTU 而卡顿白屏
        networking.nftables.tables.dn42-mss-clamp = mkIf config.networking.nftables.enable {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority mangle; policy accept;
              oifname { "dn42x*", "xfrm*" } tcp flags syn / syn,rst tcp option maxseg size set rt mtu
            }
            chain postrouting {
              type filter hook postrouting priority mangle; policy accept;
              oifname { "dn42x*", "xfrm*" } tcp flags syn / syn,rst tcp option maxseg size set rt mtu
            }
          '';
        };

        # 客户端出站源地址校正 (SNAT):
        # 当本机应用（如 Mihomo 代理进程发起 DIRECT 出站）在初次路由选路时选取了物理网卡私网 IP (如 192.168.x.x)，
        # 随后经策略路由 re-route 转发至 dn42x+ 接口出海时，强制将源地址伪装 (SNAT) 为本机的 DN42 Loopback 单播 IP (baseCfg.routerId)。
        # 确保所有经 DN42 出口加速的流量均具备合法的本机 DN42 IP，防止因私网 IP 或错误网段被出口机 drop。
        networking.nftables.tables.dn42-client-snat =
          mkIf (config.networking.nftables.enable && cfg.thisNode.endpoint == null)
            {
              family = "inet";
              content = ''
                chain postrouting {
                  type nat hook postrouting priority srcnat; policy accept;
                  oifname "dn42x*" ip saddr != 172.20.0.0/14 snat to ${baseCfg.routerId}
                }
              '';
            };

        # 防火墙放行：
        # - UDP / TCP 集群所有隧道端口 (全动态集合 allClusterTunnelPorts)
        # - UDP 6696: Babel IGP 动态路由
        # - TCP controllerPort: SD-WAN 注册中心主控端口 (仅在 Controller 节点开启)
        networking.firewall = {
          allowedUDPPorts = cfg.allClusterTunnelPorts ++ [ 6696 ];
          allowedTCPPorts =
            cfg.allClusterTunnelPorts
            ++ lib.optional (baseCfg.sdwan.enable && baseCfg.sdwan.isController) baseCfg.sdwan.controllerPort;
          extraReversePathFilterRules = ''
            udp sport { ${portsCsv} } accept
            udp dport { ${portsCsv} } accept
            tcp sport { ${portsCsv} } accept
            tcp dport { ${portsCsv} } accept
          '';
          extraCommands = mkIf (!config.networking.nftables.enable) ''
            ip46tables --append nixos-fw --protocol 50 --jump nixos-fw-accept 2>/dev/null || true
            ip46tables --append nixos-fw --protocol 51 --jump nixos-fw-accept 2>/dev/null || true
            iptables -t raw -A PREROUTING -p udp -m multiport --dports ${portsCsv} -j NOTRACK 2>/dev/null || true
            iptables -t raw -A PREROUTING -p tcp -m multiport --dports ${portsCsv} -j NOTRACK 2>/dev/null || true
            iptables -t raw -A OUTPUT -p udp -m multiport --sports ${portsCsv} -j NOTRACK 2>/dev/null || true
            iptables -t raw -A OUTPUT -p tcp -m multiport --sports ${portsCsv} -j NOTRACK 2>/dev/null || true
            ip6tables -t raw -A PREROUTING -p udp -m multiport --dports ${portsCsv} -j NOTRACK 2>/dev/null || true
            ip6tables -t raw -A PREROUTING -p tcp -m multiport --dports ${portsCsv} -j NOTRACK 2>/dev/null || true
            ip6tables -t raw -A OUTPUT -p udp -m multiport --sports ${portsCsv} -j NOTRACK 2>/dev/null || true
            ip6tables -t raw -A OUTPUT -p tcp -m multiport --sports ${portsCsv} -j NOTRACK 2>/dev/null || true
            iptables -t mangle -A FORWARD -o dn42x+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
            iptables -t mangle -A POSTROUTING -o dn42x+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
            iptables -t mangle -A FORWARD -o xfrm+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
            iptables -t mangle -A POSTROUTING -o xfrm+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
          '';
          extraInputRules = mkIf config.networking.nftables.enable ''
            meta l4proto esp counter accept
            meta l4proto ah  counter accept
            udp dport { ${portsCsv}, 6696 } counter accept
            tcp dport { ${portsCsv} } counter accept
          '';
        };

        # 针对启用了 NetworkManager 的移动节点 (arx8, surface)，切换 Wi-Fi / 有线 / 热点时自动热挂载 Mimic
        networking.networkmanager.dispatcherScripts =
          lib.mkIf (cfg.ipsec.mimic.enable && config.networking.networkmanager.enable)
            [
              {
                type = "basic";
                source = pkgs.writeText "90-mimic-roaming" ''
                  IFACE="$1"
                  ACTION="$2"
                  case "$IFACE" in
                    lo|dn42*|xfrm*|tailscale*|mihomo*|Meta*|meta*|tun*|veth*|docker*|virbr*|br-*|podman*)
                      exit 0
                      ;;
                  esac
                  case "$ACTION" in
                    up|dhcp4-change|dhcp6-change)
                      systemctl restart "mimic@$IFACE.service" || true
                      systemctl restart strongswan-swanctl.service || true
                      ;;
                    down)
                      systemctl stop "mimic@$IFACE.service" || true
                      ;;
                  esac
                '';
              }
            ];
      }
    ))

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
              // (optionalAttrs (peerCfg.endpoint != null && lib.isString peerCfg.endpoint) {
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

          # ── Direct 协议：只监听 dummy 'dn42'/'dummy0' 接口导入 Loopback /32 与 /128 ──
          protocol direct direct_dn42 {
            ipv4;
            ipv6;
            interface "dn42", "dummy0";
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

          # ── Babel IGP 导出过滤器（宣告本机 Loopback、中继内部 Loopback 与可选出口路由） ──
          filter babel_export_v4 {
            if proto = "direct_dn42" && net ~ OWNIPv4 && net.len = 32 then accept;
            if source = RTS_BABEL && net ~ OWNIPv4 && net.len = 32 then accept;
            ${optionalString cfg.exportExitRoutes ''
              if proto = "static_dn42_exit_v4" then accept;
            ''}
            if source = RTS_BABEL && net ~ [ 172.20.0.0/14, 172.31.0.0/16, 10.0.0.0/8 ] then accept;
            reject;
          }

          filter babel_export_v6 {
            if proto = "direct_dn42" && net ~ OWNIPv6 && net.len = 128 then accept;
            if source = RTS_BABEL && net ~ OWNIPv6 && net.len = 128 then accept;
            ${optionalString cfg.exportExitRoutes ''
              if proto = "static_dn42_exit_v6" then accept;
            ''}
            if source = RTS_BABEL && net = fd00::/8 then accept;
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
            # 针对 XFRM SD-WAN 网卡启用无线模式（ETX 丢包率惩罚）与 RTT 延迟测算
            interface "dn42x-*" {
              type ${cfg.babel.type};
              rxcost ${toString cfg.babel.rxCost};
              hello interval ${toString cfg.babel.helloInterval} s;
              update interval ${toString cfg.babel.updateInterval} s;
              ${optionalString cfg.babel.rttMetric ''
                send timestamps yes;
                rtt cost ${toString cfg.babel.rttCost};
                rtt min ${toString cfg.babel.rttMin} ms;
                rtt max ${toString cfg.babel.rttMax} ms;
                rtt decay ${toString cfg.babel.rttDecay};
              ''}
              extended next hop yes;
              check link yes;
            };
            ${optionalString (cfg.backend == "wireguard") ''
              interface "dn42m-*" {
                type ${cfg.babel.type};
                rxcost ${toString cfg.babel.rxCost};
                hello interval ${toString cfg.babel.helloInterval} s;
                update interval ${toString cfg.babel.updateInterval} s;
                extended next hop yes;
                check link yes;
              };
            ''}
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
