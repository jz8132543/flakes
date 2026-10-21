# =============================================================================
# DN42 节点与 Peer 拓扑配置 (Nodes, Overrides & External Peers)
# =============================================================================
# 说明：
# 1. 绝大多数节点无需在此处配置，一切依靠 core.tf 的自动 ID 推导与默认参数运行。
# 2. 仅当某台节点需要特定角色（如 border 边界网关）、自定端口或多端点时，才在 dn42_overrides 中覆盖。
# 3. 与外部自治系统（如其他 DN42 玩家）建立 eBGP 互联在 dn42_external_peers 中声明。
# =============================================================================

locals {
  # ── 1. 公网对等别名映射与 WireGuard 公钥 ──────────────────────────────────────
  # 用于为公网节点分配易记的对等别名 (例如 peer1.dora.im -> fra0.dora.im)。
  # 供外部对等方使用，并在 dns.tf 中自动发布到 Cloudflare。
  dn42_peer_targets = {
    peer1 = "fra0"
    peer2 = "sjc0"
    peer3 = "cu"
  }

  dn42_peer_aliases = local.dn42_peer_targets

  # 对应的公网对等 WireGuard 节点公钥
  dn42_peer_public_keys = {
    peer1 = "aPD/ej1dswyojJ+u41Pgsw1XSca7tMOwdhEpiv4Ntl0="
    peer2 = "k4Um5FjJ1yS7aDDvs9v9jSpUePFL7YcATFr5q79y3yU="
    peer3 = "PJ24FpCqARflKn0Cbhg/c9dG8TuViBcFrco5b2BLdw8="
  }

  # ── 2. 个别节点的特殊覆盖配置 (dn42_overrides) ──────────────────────────────
  # [参数说明]
  # - enable        : 是否为该主机启用 DN42 网络（默认: true）
  # - id            : 手动指定节点 ID (1..99)，若不指定则按 hosts.tf 顺序自动顺延推导
  # - ike_port      : 自定义 IKE 握手端口（默认: 500）
  # - nat_t_port    : 自定义 NAT-T / WireGuard 封装端口（默认: 4500）
  # - is_controller : 是否作为 SD-WAN 主控节点（默认: false，控制节点负责中心路由交换）
  # - role          : 节点角色 ("border" 边界路由器负责 eBGP / "internal" 内部专网节点)
  # - ibgp          : 是否启用完整全网 Mesh iBGP 会话
  # - endpoints     : 手动声明公网接入端点表（例如多线接入、指定 IPv4/IPv6 端口等）
  #
  # [示例] 新增特殊机器示例：
  # "example0" = {
  #   enable        = true
  #   id            = 99
  #   ike_port      = 50560
  #   nat_t_port    = 50561
  #   is_controller = false
  #   role          = "internal"
  # }
  dn42_overrides = {
    # ── SD-WAN 控制节点 (三地互备主控) ─────────────────────────────────────────
    "fra0" = {
      is_controller = true
      role          = "border"
      ibgp          = true
    }

    "sjc0" = {
      is_controller = true
      role          = "border"
      ibgp          = true
    }

    "cu" = {
      is_controller = true
      role          = "border"
      ibgp          = true
      nat_t_port    = 50568
      endpoints = {
        "cu4" = "cu.dora.im:50568"
        "cu6" = "cuv6.dora.im:50568"
        "cm4" = "cm.dora.im:50568"
        "cm6" = "cmv6.dora.im:50568"
      }
    }
  }

  # ── 3. 外部 eBGP 互联 Peers (dn42_external_peers) ───────────────────────────
  # 与 DN42 网络其他自治域的 BGP 互联会话。
  # [参数说明]
  # - host            : 本地承载该 peer 互联的边界节点名称 (必须在 dn42_nodes 中存在)
  # - asn             : 对方的 DN42 自治系统号 (ASN)
  # - endpoint        : 对方的公网 WireGuard 连接端点 (Host:Port)
  # - listenPort      : 本地 WireGuard 监听端口 (通常 51820)
  # - publicKey       : 对方的 WireGuard 公钥
  # - linkLocal       : 对方分配的 IPv6 Link-Local 地址 (用于 BGP 对等会话)
  # - ourLinkLocal    : 我方配置的 IPv6 Link-Local 地址
  # - latency         : 链路预估延迟 ("10ms" 等，用于 BGP 路径开销计算)
  # - bandwidth       : 链路预估带宽 ("1000m")
  # - crypto          : 隧道加密类型 (通常 "wireguard")
  # - extendedNextHop : 是否开启 RFC 5549 Extended Next-Hop (IPv4 over IPv6 Next-Hop)
  dn42_external_peers = {
    g-load-de2 = {
      host            = "fra0"
      asn             = 4242423914
      endpoint        = "de2.g-load.eu:20137"
      listenPort      = 51820
      publicKey       = "B1xSG/XTJRLd+GrWDsB06BqnIq8Xud93YVh/LYYYtUY="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
    g-load-hk1 = {
      host            = "cu"
      asn             = 4242423914
      endpoint        = "hk1.g-load.eu:20087"
      listenPort      = 51820
      publicKey       = "sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
    g-load-us3 = {
      host            = "sjc0"
      asn             = 4242423914
      endpoint        = "us3.g-load.eu:20031"
      listenPort      = 51820
      publicKey       = "sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
  }
}
