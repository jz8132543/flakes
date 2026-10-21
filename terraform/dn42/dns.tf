# =============================================================================
# DN42 域名解析配置 (DNS Records & Aliases for dora.dn42)
# =============================================================================
# 说明：
# 1. dora.dn42 域由专网权威 DNS (ATC CoreDNS) 托管解析。
# 2. 所有集群节点已由 core.tf 自动分配双栈 A (172.20.232.<id>) 与 AAAA (fd53:90fd:4bb6:<id>::1)。
# 3. 此文件专用于配置：
#    - 快捷别名 (CNAME)：将服务名指向已有节点或 FQDN
#    - 自定义独立记录 (A / AAAA / TXT 等)：如 VIP、Docker 容器、第三方专网服务
#    - 公网 Cloudflare 别名发布：自动同步 peer1/peer2/peer3 到公网 DNS
# =============================================================================

locals {
  # ── 1. dora.dn42 内部权威 CNAME 别名表 (dn42_cnames) ────────────────────────
  # [语法规则]
  # - 键 (Key)   : 子域名前缀，最终解析为 <Key>.dora.dn42。
  # - 值 (Value) : 目标主机。支持纯节点简称（如 "fra0"，将自动补全为 "fra0.dora.dn42."）
  #                或带末尾点号的完整 FQDN（如 "ext.other.dn42."）。
  # [DNS 规范注意]
  # - Zone Apex (根域 dora.dn42 本身) 不能设为 CNAME（因已有 SOA/NS 记录，违反 RFC 1912）。
  # - 已经配置了 CNAME 的子域名，不能再配置同名的 A / AAAA 记录。
  #
  # [示例配置] 如需启用别名，取消下方注释并添加：
  dn42_cnames = {
    # "git"    = "fra0"                     # git.dora.dn42 -> fra0.dora.dn42.
    # "matrix" = "fra0"                     # matrix.dora.dn42 -> fra0.dora.dn42.
    # "s3"     = "cu"                       # s3.dora.dn42 -> cu.dora.dn42.
    # "docs"   = "docs.otherdomain.dn42."   # 指向外部其他 DN42 域名的完整 FQDN
  }

  # ── 2. dora.dn42 自定义独立解析记录 (dn42_custom_records) ───────────────────
  # [适用场景]
  # - 为非 NixOS 管理的专网设备、Docker 容器、K8s Pod 静态分配内网域名
  # - 为高可用 Anycast / 虚拟 IP (VIP) 配置多地址解析
  # - 声明 TXT / SPF / SRV 等其他记录类型
  #
  # [参数说明]
  # - name  : 子域名前缀（如 "vault" 解析为 vault.dora.dn42）
  # - type  : DNS 记录类型（"A", "AAAA", "CNAME", "TXT", "MX" 等）
  # - value : 记录值（IPv4 地址、IPv6 地址、字符串等）
  # - ttl   : 可选，TTL 缓存秒数（默认使用 CoreDNS 全局 TTL 300）
  #
  # [示例配置]：
  dn42_custom_records = [
    # 示例 1: 双栈独立服务解析
    # { name = "vault", type = "A",    value = "172.20.232.1", ttl = 300 },
    # { name = "vault", type = "AAAA", value = "fd53:90fd:4bb6:1::1", ttl = 300 },

    # 示例 2: 专网虚拟 IP (VIP)
    # { name = "vip",   type = "A",    value = "172.20.232.50" },
    # { name = "vip",   type = "AAAA", value = "fd53:90fd:4bb6:50::1" },

    # 示例 3: TXT 记录说明
    # { name = "_info", type = "TXT",  value = "\"cluster=dn42-mesh\"" },
  ]
}

# ── 3. Cloudflare 公网对等 CNAME 记录自动发布 ────────────────────────────────
# 作用：将 peer1.dora.im -> fra0.dora.im 自动同步至公网 Cloudflare DNS，
# 方便外部对等方使用稳定固定的 Peer 域名连接我方公网 WireGuard 端口。
resource "cloudflare_dns_record" "dn42_peer_cnames" {
  for_each = var.cloudflare_zone_id != null ? local.dn42_peer_aliases : {}

  name    = "${each.key}.${var.cloudflare_zone_name}"
  proxied = false
  ttl     = 1 # automatic
  type    = "CNAME"
  content = "${each.value}.${var.cloudflare_zone_name}"
  zone_id = var.cloudflare_zone_id
}
