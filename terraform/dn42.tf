# =============================================================================
# DN42 根模块接入中心 (Root Orchestrator)
# =============================================================================
# 说明：
# 1. 本文件为 Terraform 根模块的 DN42 接入入口与全局网段变量定义。
# 2. 核心逻辑、节点 Peer 配置以及 DNS 记录已分别解耦拆分至 ./dn42/ 目录：
#    - ./dn42/core.tf  : 核心拓扑推导、ID 顺延计算、端点规范化与编码约束断言
#    - ./dn42/nodes.tf : 节点参数覆盖 (dn42_overrides)、外部 eBGP Peers 与公网对等信息
#    - ./dn42/dns.tf   : dora.dn42 权威别名 (CNAME) 与自定义 A/AAAA 记录，及 Cloudflare 发布
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

module "dn42" {
  source = "./dn42"

  hosts                = local.hosts
  dn42_asn             = var.dn42_asn
  dn42_v4_cidr         = var.dn42_v4_cidr
  dn42_v6_cidr         = var.dn42_v6_cidr
  cloudflare_zone_id   = cloudflare_zone.im_dora.id
  cloudflare_zone_name = cloudflare_zone.im_dora.name
}

# 状态平滑迁移声明：确保重构为子模块后，已有 Cloudflare DNS 记录自动继承状态，不被销毁重建
moved {
  from = cloudflare_dns_record.dn42_peer_cnames
  to   = module.dn42.cloudflare_dns_record.dn42_peer_cnames
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
  value       = module.dn42.topology
}

output "dn42_data" {
  description = "Full DN42 dataset consumed by NixOS DN42 modules"
  sensitive   = false
  value       = module.dn42.data
}
