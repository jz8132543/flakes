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
  thisHostMesh = dn42Data.mesh.${hostName} or { };

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
          default = nodeMeshCfg.ikePort or 500;
          description = "strongSwan charon.port for IKE (default 500)";
        };

        natTPort = mkOption {
          type = types.port;
          default =
            nodeMeshCfg.natTPort or (nodeMeshCfg.port or (
              if detectedPort != null && detectedPort != (nodeMeshCfg.listenPort or 51821) then
                detectedPort
              else
                4500
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
          default = hIdx;
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

  # Exclude self
  otherNodes = filterAttrs (n: _: n != hostName) cfg.nodes;

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
  selfEdgeNode = lib.findFirst (n: n.name == hostName) null (selfData.cdn.edgeNodes or [ ]);
  selfPublicIpv4 =
    if selfEdgeNode != null && selfEdgeNode ? ipv4 && selfEdgeNode.ipv4 != null then
      selfEdgeNode.ipv4
    else if hostName == "cu" then
      "cu.dora.im"
    else if hostName == "can0" then
      "can0.dora.im"
    else if
      !(thisHostMesh.nat or (builtins.elem hostName [
        "surface"
        "arx8"
        "isk"
      ])
      )
    then
      "${hostName}.dora.im"
    else
      "auto";
  selfPublicIpv6 =
    if selfEdgeNode != null && selfEdgeNode ? ipv6 && selfEdgeNode.ipv6 != null then
      selfEdgeNode.ipv6
    else if hostName == "cu" then
      "cuv6.dora.im"
    else if
      !(thisHostMesh.nat or (builtins.elem hostName [
        "surface"
        "arx8"
        "isk"
      ])
      )
    then
      "${hostName}.dora.im"
    else
      "auto";

  controllerUrls = [
    "http://fra0.dora.im:${toString baseCfg.sdwan.controllerPort}"
    "http://tyo0.dora.im:${toString baseCfg.sdwan.controllerPort}"
    "http://sjc0.dora.im:${toString baseCfg.sdwan.controllerPort}"
  ];

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
          isNat =
            meshNode.nat or (builtins.elem name [
              "surface"
              "arx8"
              "isk"
            ]);
          pubIpv4 =
            if edgeNode != null && edgeNode ? ipv4 && edgeNode.ipv4 != null then
              edgeNode.ipv4
            else if name == "cu" then
              "cu.dora.im"
            else if !isNat then
              "${name}.dora.im"
            else
              "";
          pubIpv6 =
            if edgeNode != null && edgeNode ? ipv6 && edgeNode.ipv6 != null then
              edgeNode.ipv6
            else if name == "cu" then
              "cuv6.dora.im"
            else
              "";
          natTPort = if name == "cu" then 50561 else (meshNode.natTPort or 4500);
          ikePort = if name == "cu" then 50560 else (meshNode.ikePort or 500);
        in
        {
          id = hIdx;
          dn42_ip4 = v4;
          dn42_ip6 = v6;
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
    REGISTRY_DIR="/var/lib/dn42-sdwan"
    REGISTRY_FILE="$REGISTRY_DIR/registry.json"
    mkdir -p "$REGISTRY_DIR"

    if [ ! -s "$REGISTRY_FILE" ]; then
      cp "${bootstrapPeersFile}" "$REGISTRY_FILE"
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
      if echo "$body" | ${pkgs.jq}/bin/jq -e 'type == "object"' >/dev/null 2>&1; then
        PEER_ADDR="''${SOCAT_PEERADDR:-127.0.0.1}"
        PROCESSED_BODY=$(echo "$body" | ${pkgs.jq} --arg ip "$PEER_ADDR" '
          to_entries | map(
            .value as $val |
            if $val.ipv4 == "auto" or $val.ipv4 == "" then
              if ($ip | contains(".")) then .value.ipv4 = $ip else . end
            else . end |
            if $val.ipv6 == "auto" or $val.ipv6 == "" then
              if ($ip | contains(":")) then .value.ipv6 = $ip else . end
            else . end
          ) | from_entries
        ')

        (
          flock -x 200
          ${pkgs.jq}/bin/jq -s '
            (.[0] // {}) as $orig | (.[1] // {}) as $new |
            reduce ($new | to_entries[]) as $item ($orig;
              if (.[$item.key] == null) or (($item.value.updated_at // 0) >= (.[$item.key].updated_at // 0))
              then .[$item.key] = $item.value
              else . end
            )
          ' "$REGISTRY_FILE" <(echo "$PROCESSED_BODY") > "$REGISTRY_FILE.tmp"
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

        # 1. 若本地缓存不存在，先用 Nix 编译期的 bootstrapPeersJson 初始化
        if [ ! -s "$CACHE_FILE" ]; then
          cp "${bootstrapPeersFile}" "$CACHE_FILE"
        fi

        SELF_NAME="${hostName}"
        SELF_ID="${toString selfNodeId}"
        SELF_IP4="${selfDn42Ip4}"
        SELF_IP6="${selfDn42Ip6}"
        SELF_PORT="${toString baseCfg.natTPort}"
        SELF_IKE_PORT="${toString baseCfg.ikePort}"
        CONTROLLERS=(${lib.concatStringsSep " " controllerUrls})

        # 2. 向 3 台主控上报本机状态，并拉取最新全网节点表合并到本地缓存
        NOW=$(date +%s)
        SELF_PAYLOAD=$(jq -n \
          --arg name "$SELF_NAME" \
          --argjson id "$SELF_ID" \
          --arg dn42_ip4 "$SELF_IP4" \
          --arg dn42_ip6 "$SELF_IP6" \
          --arg ipv4 "${selfPublicIpv4}" \
          --arg ipv6 "${selfPublicIpv6}" \
          --argjson nat_t_port "$SELF_PORT" \
          --argjson ike_port "$SELF_IKE_PORT" \
          --arg pubkey "" \
          --argjson updated_at "$NOW" \
          '{($name): {id: $id, dn42_ip4: $dn42_ip4, dn42_ip6: $dn42_ip6, ipv4: $ipv4, ipv6: $ipv6, nat_t_port: $nat_t_port, ike_port: $ike_port, pubkey: $pubkey, updated_at: $updated_at}}')

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

        # 3. 遍历 peers.json，热创建/维护 dn42x-<peer> 接口与 swanctl 配置文件
        CONF_CHANGED=0
        HOSTS_TMP="/run/dn42-hosts.tmp"
        : > "$HOSTS_TMP"

        for peer in $(jq -r 'keys[]' "$CACHE_FILE"); do
          PEER_IP4=$(jq -r --arg p "$peer" '.[$p].dn42_ip4 // empty' "$CACHE_FILE")
          [ -z "$PEER_IP4" ] && continue
          echo "$PEER_IP4 ''${peer}.dn42" >> "$HOSTS_TMP"

          [ "$peer" = "$SELF_NAME" ] && continue

          PEER_ID=$(jq -r --arg p "$peer" '.[$p].id // empty' "$CACHE_FILE")
          [ -z "$PEER_ID" ] && continue

          PEER_PUB_IP4=$(jq -r --arg p "$peer" '.[$p].ipv4 // empty' "$CACHE_FILE")
          PEER_PUB_IP6=$(jq -r --arg p "$peer" '.[$p].ipv6 // empty' "$CACHE_FILE")
          PEER_PORT=$(jq -r --arg p "$peer" '.[$p].nat_t_port // 4500' "$CACHE_FILE")
          [ -z "$PEER_PORT" ] && PEER_PORT=4500

          IFACE="dn42x-''${peer}"

          # 3a. 确保 XFRM 接口存在、MTU=1360、关闭 GSO/TX offload 并配置好内网 IP 与 fe80:: Link-Local
          if ! ip link show "$IFACE" >/dev/null 2>&1; then
            ip link add "$IFACE" type xfrm dev lo if_id "$PEER_ID"
          fi
          ip link set "$IFACE" mtu 1360 up
          ethtool -K "$IFACE" tx off gso off gro off 2>/dev/null || true

          ip -4 addr replace "''${SELF_IP4}/32" peer "''${PEER_IP4}/32" dev "$IFACE" 2>/dev/null || true
          ip -6 addr replace "fe80::''${SELF_ID}/64" dev "$IFACE" 2>/dev/null || true
          [ -n "$SELF_IP6" ] && ip -6 addr replace "''${SELF_IP6}/128" dev "$IFACE" 2>/dev/null || true

          # 3b. 生成该对端的 swanctl 独立连接配置
          REMOTE_ADDRS=()
          [ -n "$PEER_PUB_IP4" ] && [ "$PEER_PUB_IP4" != "auto" ] && REMOTE_ADDRS+=("$PEER_PUB_IP4")
          [ -n "$PEER_PUB_IP6" ] && [ "$PEER_PUB_IP6" != "auto" ] && REMOTE_ADDRS+=("$PEER_PUB_IP6")

          if [ ''${#REMOTE_ADDRS[@]} -eq 0 ]; then
            REMOTE_ADDR_STR="%any"
            CHILD_START_ACTION="none"
            CHILD_DPD_ACTION="clear"
          else
            REMOTE_ADDR_STR=$(IFS=,; echo "''${REMOTE_ADDRS[*]}")
            CHILD_START_ACTION="trap|start"
            CHILD_DPD_ACTION="restart"
          fi

          PEER_CONF="$SWAN_D/sdwan-''${peer}.conf"
          NEW_CONTENT=$(cat <<EOF
    connections {
      dn42-''${peer} {
        version = 2
        mobike = yes
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        dpd_timeout = 120s
        local_port = ''${SELF_PORT}
        remote_port = ''${PEER_PORT}
        local_addrs = %any
        remote_addrs = ''${REMOTE_ADDR_STR}

        proposals = aes256gcm128-sha256-x25519, chacha20poly1305-sha256-x25519, aes128gcm128-sha256-x25519

        local {
          auth = psk
          id = ''${SELF_NAME}.dn42
        }
        remote {
          auth = psk
          id = ''${peer}.dn42
        }
        children {
          dn42-''${peer} {
            esp_proposals = aes256gcm128-x25519, chacha20poly1305-x25519, aes128gcm128-x25519
            local_ts = 0.0.0.0/0, ::/0
            remote_ts = 0.0.0.0/0, ::/0
            if_id_in = ''${PEER_ID}
            if_id_out = ''${PEER_ID}
            set_mark_out = 0x1
            mode = tunnel
            start_action = ''${CHILD_START_ACTION}
            dpd_action = ''${CHILD_DPD_ACTION}
          }
        }
      }
    }
    EOF
    )

          if [ ! -f "$PEER_CONF" ] || [ "$NEW_CONTENT" != "$(cat "$PEER_CONF" 2>/dev/null || true)" ]; then
            echo "$NEW_CONTENT" > "$PEER_CONF"
            CONF_CHANGED=1
          fi
        done

        mv "$HOSTS_TMP" /run/dn42-hosts

        # 4. 仅在配置真正发生变化时增量热重载 strongSwan，不中断已有连接
        if [ "$CONF_CHANGED" -eq 1 ]; then
          swanctl --load-all --noprompt 2>/dev/null || true
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
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
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
            OnUnitActiveSec = "45s";
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
        networking.firewall = {
          allowedUDPPorts = cfg.allClusterTunnelPorts ++ [ 6696 ];
          allowedTCPPorts = cfg.allClusterTunnelPorts;
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
