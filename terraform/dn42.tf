# =============================================================================
# DN42 自动化拓扑与默认值中心 (Zero-Touch Configuration)
# 说明：
# 1. 所有在 hosts.tf (或 nixos/hosts) 中定义的节点均会自动启用 DN42 并套用默认值。
# 2. 新增普通机器时，【无需修改本文件】，一切依靠默认值与自动 ID 推导完成。
# 3. 仅当某台机器需要特殊覆盖默认参数时，才在下方的 dn42_overrides 中取消注释并配置。
# =============================================================================

variable "dn42_asn" {
  default = 4242420115
  type    = number
}

variable "dn42_v4_cidr" {
  default = "172.20.232.0/26"
  type    = string
}

variable "dn42_v6_cidr" {
  default = "fd53:90fd:4bb6::/48"
  type    = string
}

locals {
  # ── 1. 公网对等别名 (peer1, peer2, peer3 ... .dora.im) ───────────────────────
  dn42_peer_targets = {
    peer1 = "fra0"
    peer2 = "hkg0"
    peer3 = "cu"
  }

  dn42_peer_aliases = local.dn42_peer_targets

  dn42_peer_public_keys = {
    peer1 = "aPD/ej1dswyojJ+u41Pgsw1XSca7tMOwdhEpiv4Ntl0="
    peer2 = "k4Um5FjJ1yS7aDDvs9v9jSpUePFL7YcATFr5q79y3yU="
    peer3 = "PJ24FpCqARflKn0Cbhg/c9dG8TuViBcFrco5b2BLdw8="
  }

  # ── 2. 个别节点的特殊覆盖配置（默认留空，所有节点均走自动化默认值） ─────────
  dn42_overrides = {
    /* -------------------------------------------------------------------------
    # [注释示例] 如需为某台新机器覆盖默认 DN42 配置，可参考以下格式取消注释：
    "example0" = {
      enable        = true          # 是否启用 DN42 (默认: true)
      id            = 99            # 手动指定节点 ID (默认: 自动根据主机列表顺延分配)
      ike_port      = 50560         # 自定义 IKE 端口 (默认: 500)
      nat_t_port    = 50561         # 自定义 NAT-T / Mimic 端口 (默认: 4500)
      is_controller = false         # 是否作为 SD-WAN 主控节点 (默认: fra0/tyo0/sjc0 为 true)
    }
    ------------------------------------------------------------------------- */

    # 针对 cu 节点的 1:1 端口映射特例（也可完全交由 nixos/hosts/cu/default.nix 处理）
    "cu" = {
      ike_port   = 50560
      nat_t_port = 50561
    }
  }

  # 自动汇总所有主机名称（直接继承自 hosts.tf 中的主机集合，保持确定性排序）
  all_host_names = sort(keys(local.hosts))

  # 为所有节点自动生成最终的 DN42 参数（合并默认值与 dn42_overrides）
  dn42_nodes = {
    for idx, name in local.all_host_names : name => merge(
      {
        enable = true
        # 若原 hosts.tf 中已有固定 host_indices/id 则沿用，否则按排序索引自动分配唯一 ID
        id            = try(local.hosts[name].id, try(local.hosts[name].host_indices[0], idx + 1))
        ike_port      = 500
        nat_t_port    = 4500
        is_controller = contains(["fra0", "tyo0", "sjc0"], name)
        role          = contains(["fra0", "hkg0", "cu"], name) ? "border" : "internal"
        ibgp          = contains(["fra0", "hkg0", "cu"], name)
      },
      lookup(local.dn42_overrides, name, {})
    )
    if try(lookup(local.dn42_overrides, name, {}).enable, true)
  }

  # ── 3. 外部 eBGP 互联 Peers ────────────────────────────────────────────────
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
      host            = "hkg0"
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
    g-load-uk1 = {
      host            = "cu"
      asn             = 4242423914
      endpoint        = "uk1.g-load.eu:20031"
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

# ── Cloudflare CNAME 记录自动发布 ───────────────────────────────────────────
resource "cloudflare_dns_record" "dn42_peer_cnames" {
  for_each = local.dn42_peer_aliases

  name    = "${each.key}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1 # automatic
  type    = "CNAME"
  content = "${each.value}.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

output "dn42_v4_cidr" {
  value     = var.dn42_v4_cidr
  sensitive = false
}

output "dn42_v6_cidr" {
  value     = var.dn42_v6_cidr
  sensitive = false
}

# 自动导出供 NixOS (lib/data/data.json) 与 SD-WAN 种子表使用的结构化输出
output "dn42_topology" {
  description = "Auto-generated DN42 node metadata with zero manual boilerplate"
  value       = local.dn42_nodes
}

output "dn42_data" {
  description = "Full DN42 dataset consumed by NixOS DN42 modules"
  sensitive   = false
  value = {
    asn            = var.dn42_asn
    ipv4           = var.dn42_v4_cidr
    ipv6           = var.dn42_v6_cidr
    mesh           = local.dn42_nodes
    topology       = local.dn42_nodes
    externalPeers  = local.dn42_external_peers
    peerAliases    = local.dn42_peer_aliases
    peerPublicKeys = local.dn42_peer_public_keys
  }
}
