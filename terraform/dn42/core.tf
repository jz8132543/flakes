# =============================================================================
# DN42 自动化拓扑核心计算引擎 (Core Engine & Data Synthesizer)
# =============================================================================
# 说明：
# 本文件包含整个 DN42 网络拓扑的纯函数式自动化推导与数据聚合：
# 1. 自动根据主机列表推导唯一节点 ID、默认端口与角色；
# 2. 规范化节点公网端点 (IPv4/IPv6 正则提取与端口解析)；
# 3. 对节点 ID 范围 (1..99) 与端点数 (<=9) 进行对称 if_id 编码约束断言；
# 4. 汇总节点、Peer、DNS 别名与自定义记录，输出结构化数据供 NixOS (lib/data/data.json) 消费。
# =============================================================================

locals {
  # 自动汇总所有主机名称（直接继承自 hosts.tf 中的主机集合，保持确定性排序）
  all_host_names = sort(keys(var.hosts))

  # 为所有节点自动生成最终的 DN42 参数（合并默认值与 dn42_overrides，纯逻辑推导）
  dn42_nodes = {
    for idx, name in local.all_host_names : name => merge(
      {
        enable = true
        # 若原 hosts.tf 中已有固定 host_indices/id 则沿用，否则按排序索引自动分配唯一 ID
        id            = try(var.hosts[name].id, try(var.hosts[name].host_indices[0], idx + 1))
        ike_port      = 500
        nat_t_port    = 4500
        is_controller = false
        role          = "internal"
        ibgp          = false
        nat           = length(try(var.hosts[name].records, {})) == 0
        endpoints = try(local.dn42_overrides[name].endpoints, (
          length(try(var.hosts[name].records, {})) > 0 ? {
            "default" = "${name}.dora.im:${try(local.dn42_overrides[name].nat_t_port, 4500)}"
          } : {}
        ))
      },
      lookup(local.dn42_overrides, name, {})
    )
    if try(lookup(local.dn42_overrides, name, {}).enable, true)
  }

  # 规范化所有端点来源为结构化对象数组，包含 host/ip、port 以及协议簇 (ipv4/ipv6)
  dn42_nodes_normalized = {
    for name, node in local.dn42_nodes : name => merge(node, {
      endpoints = [
        for endpoint_name, endpoint_value in try(node.endpoints, {}) : {
          name = endpoint_name
          addr = (
            can(regex("^\\[(.*)\\]:[0-9]+$", endpoint_value))
            ? regex("^\\[(.*)\\]:[0-9]+$", endpoint_value)[0]
            : regex("^([^:]+)(?::[0-9]+)?$", endpoint_value)[0]
          )
          port = (
            can(regex("\\]:([0-9]+)$", endpoint_value))
            ? tonumber(regex("\\]:([0-9]+)$", endpoint_value)[0])
            : (
              can(regex(":([0-9]+)$", endpoint_value))
              ? tonumber(regex(":([0-9]+)$", endpoint_value)[0])
              : try(node.nat_t_port, 4500)
            )
          )
          # 包含冒号的为字面 IPv6；域名则根据命名约定 (包含 v6/6 视为 IPv6，否则为 IPv4)
          family = (
            strcontains(
              (
                can(regex("^\\[(.*)\\]:[0-9]+$", endpoint_value))
                ? regex("^\\[(.*)\\]:[0-9]+$", endpoint_value)[0]
                : regex("^([^:]+)(?::[0-9]+)?$", endpoint_value)[0]
              ), ":"
            )
            ? "ipv6"
            : (
              can(regex("(v6|6)$", endpoint_name))
              ? "ipv6"
              : "ipv4"
            )
          )
        }
      ]
    })
  }
}

# ── if_id 编码约束断言 ───────────────────────────────────────────────────────
# SD-WAN 子链路采用对称 if_id = min(A,B)*1000 + max(A,B)*10 + k，因此严格要求：
#   1. 节点 ID 落在 1..99（千位/十位编码不冲突）
#   2. 单节点端点数量 <= 9（个位 k 序号不冲突）
#   3. 所有端点端口合法 (1..65535)
data "assert_test" "dn42_node_id_range" {
  test  = length([for name, node in local.dn42_nodes : name if node.id < 1 || node.id >= 100]) == 0
  throw = "dn42 node id must be within 1..99 (symmetric if_id encoding min*1000 + max*10 + k)"
}

data "assert_test" "dn42_endpoint_count" {
  test  = length([for name, node in local.dn42_nodes_normalized : name if length(node.endpoints) > 9]) == 0
  throw = "dn42 node must publish at most 9 endpoints (symmetric if_id encoding min*1000 + max*10 + k)"
}

data "assert_test" "dn42_endpoint_ports" {
  test = length(flatten([
    for name, node in local.dn42_nodes_normalized : [
      for ep in node.endpoints : "${name}/${ep.name}" if ep.port < 1 || ep.port > 65535
    ]
  ])) == 0
  throw = "dn42 endpoint ports must be within 1..65535"
}

# ── 模块数据输出 (Outputs) ───────────────────────────────────────────────────

output "topology" {
  description = "Auto-generated DN42 node metadata with zero manual boilerplate"
  value       = local.dn42_nodes_normalized
}

output "data" {
  description = "Full DN42 dataset consumed by NixOS DN42 modules"
  sensitive   = false
  value = {
    domain         = "dora.dn42"
    asn            = var.dn42_asn
    ipv4           = var.dn42_v4_cidr
    ipv6           = var.dn42_v6_cidr
    schema         = 2
    mesh           = local.dn42_nodes_normalized
    topology       = local.dn42_nodes_normalized
    externalPeers  = local.dn42_external_peers
    peerAliases    = local.dn42_peer_aliases
    peerPublicKeys = local.dn42_peer_public_keys
    cnames         = local.dn42_cnames
    customRecords  = local.dn42_custom_records
  }
}
