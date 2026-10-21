# =============================================================================
# DN42 模块入参变量 (Module Variables)
# =============================================================================

variable "hosts" {
  description = "根模块 hosts.tf 中定义的全部主机字典 (local.hosts)"
  type        = any
}

variable "dn42_asn" {
  description = "DN42 网络自治系统号 (ASN)"
  type        = number
  default     = 4242420115
}

variable "dn42_v4_cidr" {
  description = "DN42 IPv4 分配网段"
  type        = string
  default     = "172.20.232.0/26"
}

variable "dn42_v6_cidr" {
  description = "DN42 IPv6 分配网段"
  type        = string
  default     = "fd53:90fd:4bb6::/48"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID（用于发布公网对等别名 peer1/peer2/peer3 CNAME）"
  type        = string
  default     = null
}

variable "cloudflare_zone_name" {
  description = "Cloudflare Zone 名称（如 dora.im）"
  type        = string
  default     = null
}
