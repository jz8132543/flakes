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
    listToAttrs
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
            (cfg.multipath.enable || (lib.elem name cfg.multipath.peers))
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
  tunnelInstances = lib.flatten (
    lib.mapAttrsToList (
      peerName: peerCfg:
      let
        baseXfrmId = 4200 + (if peerCfg.hostIndex != null then peerCfg.hostIndex else 99);
        epList = lib.mapAttrsToList (name: addr: { inherit name addr; }) peerCfg.endpoints;
      in
      if peerCfg.multipath && epList != [ ] then
        lib.imap0 (i: ep: {
          key = "${peerName}-${ep.name}";
          inherit peerName peerCfg;
          epName = ep.name;
          epAddr = stripPort ep.addr;
          ifName = "dn42x-${lib.substring 0 5 peerName}-${ep.name}";
          xfrmId = 42000 + (if peerCfg.hostIndex != null then peerCfg.hostIndex * 10 else 990) + i;
          remoteAddrs = [
            (stripPort ep.addr)
            "%any"
          ];
        }) epList
      else
        let
          # 单隧道模式：按优先级自动排列所有候选端点（IPv6 优先、IPv4 兜底、多出口节点全量候选）
          sortedCandidateAddrs =
            let
              rawAddrs =
                if epList != [ ] then
                  map (ep: stripPort ep.addr) epList
                else
                  (lib.optional (peerCfg.endpoint != null && lib.isString peerCfg.endpoint) (
                    stripPort peerCfg.endpoint
                  ))
                  ++ (lib.optional (peerCfg.endpointV6 != null) peerCfg.endpointV6);
            in
            lib.unique rawAddrs;
        in
        [
          {
            key = peerName;
            inherit peerName peerCfg;
            epName = "default";
            epAddr = if sortedCandidateAddrs != [ ] then lib.head sortedCandidateAddrs else null;
            ifName = "dn42x-${lib.substring 0 9 peerName}";
            xfrmId = baseXfrmId;
            remoteAddrs = sortedCandidateAddrs ++ [ "%any" ];
          }
        ]
    ) activePeers
  );

  # ── Mimic Fake-TCP 启动包装脚本 ──
  # 1. 彻底移除引起内核 TC_ACT_SHOT 丢包的 act_csum 脚本；
  # 2. 网卡层关闭 TX/RX 硬件校验和卸载与 GRO，迫使内核在 TC Egress 软件计算完整校验和；
  # 3. 动态提取本机真实网卡 Global IP 以及通配符，全网集群节点均运行 Mimic，天然对称互通，无需脆弱的 remote 白名单；
  # 4. 强制使用 --xdp-mode skb，完全规避 virtio_net 驱动级 XDP 挂载/尾部调整失败问题。
  mimicStartScript = pkgs.writeShellScript "mimic-start-wrapper" ''
    set -euo pipefail
    IFACE="$1"

    # 1. 清理该网卡上可能残留的旧 BPF clsact qdisc、XDP 挂载与 /run/mimic 锁文件（彻底根除 EEXIST status=17 循环崩溃）
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

    # 2. 关闭 GRO/LRO 以及 TX/RX 硬件校验和卸载：
    #    - 关 gro/lro：防止 skb-XDP 模式下多个 Fake-TCP 包被合并破坏 12 字节尾部边界
    #    - 关 tx/rx csum offload：迫使内核在进入 Mimic (TC Egress) 前完成软件校验和计算，且接收端网卡不因 IPv4 ESP 零校验和丢弃 Fake-TCP 包
    ${pkgs.ethtool}/bin/ethtool -K "$IFACE" gro off rx-gro-hw off lro off gso off tso off tx off rx off 2>/dev/null || true
    ${pkgs.ethtool}/bin/ethtool -K "$IFACE" tx-udp_tnl-segmentation off tx-udp_tnl-csum-segmentation off 2>/dev/null || true

    # 如果暂未获得 Global IP，短暂等待最多 5 秒
    for i in $(seq 1 5); do
      if [ -n "$(${pkgs.iproute2}/bin/ip -o addr show dev "$IFACE" scope global 2>/dev/null)" ]; then
        break
      fi
      sleep 1
    done

    FILTER_ARGS=()
    if [ "${if cfg.ipsec.mimic.allTraffic then "1" else "0"}" = "1" ]; then
      FILTER_ARGS+=(
        "-f" "local=0.0.0.0:4500"
        "-f" "local=[::]:4500"
        "-f" "local=0.0.0.0:500"
        "-f" "local=[::]:500"
        "-f" "remote=0.0.0.0:4500"
        "-f" "remote=[::]:4500"
        "-f" "remote=0.0.0.0:500"
        "-f" "remote=[::]:500"
      )
    else
      ${lib.concatMapStringsSep "\n" (
        peerName:
        let
          peerCfg = otherNodes.${peerName} or null;
          peerEndpoints =
            if peerCfg == null then
              [ "${peerName}.dora.im" ]
            else if (peerCfg.endpoints or { }) != { } then
              lib.mapAttrsToList (_: stripPort) peerCfg.endpoints
            else if peerCfg.endpoint != null then
              if lib.isString peerCfg.endpoint then
                [ (stripPort peerCfg.endpoint) ]
              else if lib.isAttrs peerCfg.endpoint then
                lib.mapAttrsToList (_: stripPort) peerCfg.endpoint
              else
                [ "${peerName}.dora.im" ]
            else
              [ "${peerName}.dora.im" ];
          formatEp = ep: if lib.hasInfix ":" ep && !lib.hasPrefix "[" ep then "[${ep}]" else ep;
        in
        lib.concatMapStringsSep "\n" (
          rawEp:
          let
            ep = formatEp rawEp;
          in
          ''
            FILTER_ARGS+=("-f" "remote=${ep}:4500")
            FILTER_ARGS+=("-f" "remote=${ep}:500")
          ''
        ) peerEndpoints
      ) cfg.ipsec.mimic.peers}
    fi

    ${lib.concatMapStringsSep "\n" (f: ''
      FILTER_ARGS+=("-f" "${f}")
    '') cfg.ipsec.mimic.extraFilters}

    echo "Starting mimic on $IFACE with xdp-mode ${cfg.ipsec.mimic.xdpMode} and filters: ''${FILTER_ARGS[*]}"
    exec ${pkgs.mimic}/bin/mimic run "$IFACE" --xdp-mode ${cfg.ipsec.mimic.xdpMode} "''${FILTER_ARGS[@]}"
  '';

in
{
  imports = [
    ./base.nix
    ./sdn.nix
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

      port = mkOption {
        type = types.port;
        default = 4500;
        description = "Standard strongSwan NAT-T UDP port for cluster mesh";
      };

      clientPort = mkOption {
        type = types.port;
        default = 4500;
        description = "NAT client NAT-T port (defaults symmetrically to 4500)";
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

      environment.systemPackages = [
        pkgs.strongswan
      ];

      # XFRM 虚拟网络网卡管理与 Mimic Fake-TCP 守护服务
      systemd.services =
        (listToAttrs (
          map (
            t:
            nameValuePair t.ifName {
              description = "DN42 XFRM interface for tunnel ${t.key}";
              after = [ "network-pre.target" ];
              wants = [ "network-pre.target" ];
              before = [
                "bird.service"
                "strongswan-swanctl.service"
              ];
              wantedBy = [ "multi-user.target" ];
              path = [
                pkgs.iproute2
                pkgs.gawk
                pkgs.ethtool
                pkgs.coreutils
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "${t.ifName}-up" ''
                  set -eu
                  if ! ip link show ${t.ifName} >/dev/null 2>&1; then
                    ip link add ${t.ifName} type xfrm if_id ${toString t.xfrmId}
                  fi
                  ip link set ${t.ifName} mtu ${toString cfg.ipsec.mtu} multicast on up
                  ${pkgs.ethtool}/bin/ethtool -K ${t.ifName} tx off gso off gro off 2>/dev/null || true
                  ip -6 addr replace ${baseCfg.linkLocalIpv6} dev ${t.ifName}
                '';
                ExecStop = pkgs.writeShellScript "${t.ifName}-down" ''
                  ip link del ${t.ifName} 2>/dev/null || true
                '';
              };
            }
          ) tunnelInstances
        ))
        // (optionalAttrs cfg.ipsec.mimic.enable {
          "mimic@" = {
            description = "Mimic eBPF UDP-4500/500 to Fake-TCP on %I";
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
              RestartSec = "2s";
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
        })
        // (optionalAttrs cfg.ipsec.mimic.enable {
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
        })
        // {
          strongswan-swanctl = {
            after = [
              "network-online.target"
            ]
            ++ lib.optional cfg.ipsec.mimic.enable "dn42-mimic-autobind.service";
            wants = [
              "network-online.target"
            ]
            ++ lib.optional cfg.ipsec.mimic.enable "dn42-mimic-autobind.service";
          };
        };

      # 针对固定服务器节点（未启用 NetworkManager），开机自动启动物理出口网卡上的 mimic 服务实例
      systemd.targets.multi-user.wants = mkIf (
        cfg.ipsec.mimic.enable && !config.networking.networkmanager.enable
      ) (map (iface: "mimic@${iface}.service") cfg.ipsec.mimic.interfaces);

      # 若系统启用了 systemd-networkd，设置该接口为 Unmanaged 防止被 networkd 重置
      systemd.network.networks = mkIf config.systemd.network.enable (
        listToAttrs (
          map (
            t:
            nameValuePair "70-${t.ifName}" {
              matchConfig.Name = t.ifName;
              linkConfig.Unmanaged = true;
            }
          ) tunnelInstances
        )
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
            port = 500
            port_nat_t = ${toString cfg.ipsec.port}
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
          connections = listToAttrs (
            map (
              t:
              let
                isV6 =
                  t.epAddr != null
                  && (lib.hasInfix ":" t.epAddr || lib.hasInfix "v6" t.epAddr || lib.hasInfix "v6" (t.epName or ""));
                # 当对端节点处于 NAT 状态时，服务端在 IPv4 上必须作为被动接收方 (passive responder)
                # 绝不能主动向其发起握手重试，避免死锁及动态 NAT 端口映射混乱
                isPassiveResponder = (t.peerCfg.nat or false) && !isV6;
              in
              nameValuePair "mesh-peer-${t.key}" {
                version = 2;
                mobike = true;
                dpd_delay = "30s";
                dpd_timeout = "120s";
                keyingtries =
                  if isPassiveResponder then
                    1
                  else if t.epAddr != null then
                    0
                  else
                    1;

                local_port = cfg.ipsec.port;
                remote_port = cfg.ipsec.port;
                remote_addrs = if isPassiveResponder then [ "%any" ] else t.remoteAddrs;
                encap = true; # 强制封装为 UDP 4500，由 Mimic 转换为 Fake-TCP 4500，防止裸 ESP 泄露被丢弃

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
                  id = "${t.peerName}.dn42";
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
                  if_id_in = toString t.xfrmId;
                  if_id_out = toString t.xfrmId;
                  # 内核 XFRM 出向 SA 原生标记：使加密后的外层 ESP/UDP 报文直接打上 mark 0x1，走 main 表默认网关，彻底避免 netfilter mangle 篡改引发的内核重新选路丢包
                  set_mark_out = "0x1";
                  # hw_offload = auto: 若网卡支持 IPsec Offload 则硬件卸载，否则无缝使用 CPU AES-NI 加速
                  hw_offload = cfg.ipsec.hwOffload;
                  mode = "tunnel";
                  start_action =
                    if isPassiveResponder then
                      "none"
                    else if t.epAddr != null then
                      "start"
                    else
                      "none";
                  dpd_action =
                    if isPassiveResponder then
                      "clear"
                    else if t.epAddr != null then
                      "restart"
                    else
                      "clear";
                };
              }
            ) tunnelInstances
          );

          secrets.ike = mkIf (cfg.ipsec.pskFile == null) {
            mesh = {
              secret = cfg.ipsec.psk;
            };
          };
        };

        includes = optional (cfg.ipsec.pskFile != null) cfg.ipsec.pskFile;
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

      # 消除冲突 1：在 nftables raw 阶段 (priority -300) 彻底绕过 nf_conntrack
      # 无论底层是原生 UDP 还是 Mimic 伪装后的 Fake-TCP，一律跳过连接跟踪，杜绝 INVALID 丢包
      networking.nftables.tables."dn42-mimic-raw" = mkIf config.networking.nftables.enable {
        family = "inet";
        content = ''
          chain raw_prerouting {
            type filter hook prerouting priority raw; policy accept;
            udp sport { 500, 4500 } notrack
            udp dport { 500, 4500 } notrack
            tcp sport { 500, 4500 } notrack
            tcp dport { 500, 4500 } notrack
          }

          chain raw_output {
            type filter hook output priority raw; policy accept;
            udp sport { 500, 4500 } notrack
            udp dport { 500, 4500 } notrack
            tcp sport { 500, 4500 } notrack
            tcp dport { 500, 4500 } notrack
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
      # - UDP 500 / 4500: StrongSwan IKEv2 与 NAT-T 原生端口
      # - TCP 500 / 4500: Mimic Fake-TCP 端口
      # - UDP 6696: Babel IGP 动态路由
      networking.firewall = {
        allowedUDPPorts = [
          500
          4500
          6696
        ];
        allowedTCPPorts = [
          500
          4500
        ];
        extraReversePathFilterRules = ''
          udp sport { 500, 4500 } accept
          udp dport { 500, 4500 } accept
          tcp sport { 500, 4500 } accept
          tcp dport { 500, 4500 } accept
        '';
        extraCommands = mkIf (!config.networking.nftables.enable) ''
          ip46tables --append nixos-fw --protocol 50 --jump nixos-fw-accept 2>/dev/null || true
          ip46tables --append nixos-fw --protocol 51 --jump nixos-fw-accept 2>/dev/null || true
          iptables -t raw -A PREROUTING -p udp -m multiport --dports 500,4500 -j NOTRACK 2>/dev/null || true
          iptables -t raw -A PREROUTING -p tcp -m multiport --dports 500,4500 -j NOTRACK 2>/dev/null || true
          iptables -t raw -A OUTPUT -p udp -m multiport --sports 500,4500 -j NOTRACK 2>/dev/null || true
          iptables -t raw -A OUTPUT -p tcp -m multiport --sports 500,4500 -j NOTRACK 2>/dev/null || true
          ip6tables -t raw -A PREROUTING -p udp -m multiport --dports 500,4500 -j NOTRACK 2>/dev/null || true
          ip6tables -t raw -A PREROUTING -p tcp -m multiport --dports 500,4500 -j NOTRACK 2>/dev/null || true
          ip6tables -t raw -A OUTPUT -p udp -m multiport --sports 500,4500 -j NOTRACK 2>/dev/null || true
          ip6tables -t raw -A OUTPUT -p tcp -m multiport --sports 500,4500 -j NOTRACK 2>/dev/null || true
          iptables -t mangle -A FORWARD -o dn42x+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
          iptables -t mangle -A POSTROUTING -o dn42x+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
          iptables -t mangle -A FORWARD -o xfrm+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
          iptables -t mangle -A POSTROUTING -o xfrm+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        '';
        extraInputRules = mkIf config.networking.nftables.enable ''
          meta l4proto esp counter accept
          meta l4proto ah  counter accept
          udp dport { 500, 4500, 6696 } counter accept
          tcp dport { 500, 4500 } counter accept
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
            # 兼容监听 IPsec (dn42x-*, xfrm*) 与 WireGuard (dn42m-*) 内部网卡，排除外部 eBGP 网卡
            interface "dn42x-*", "dn42m-*", "xfrm*" {
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
