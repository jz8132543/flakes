variable "host_indices" {
  type    = list(number)
  default = [1]
}
variable "dn42_v4_cidr" {
  type    = string
  default = "172.20.232.0/26"
}
variable "dn42_v6_cidr" {
  type    = string
  default = "fd53:90fd:4bb6::/48"
}
variable "enable_dn42" {
  type    = bool
  default = true
}
variable "ike_port" {
  type    = number
  default = 500
}
variable "nat_t_port" {
  type    = number
  default = 4500
}
variable "is_controller" {
  type    = bool
  default = false
}

locals {
  dn42_v4_prefix_length = tonumber(regex(".*/([[:digit:]]+)", var.dn42_v4_cidr)[0])
  dn42_v6_prefix_length = tonumber(regex(".*/([[:digit:]]+)", var.dn42_v6_cidr)[0])
  dn42_addresses_v4     = [for i in var.host_indices : cidrhost(var.dn42_v4_cidr, i)]
  dn42_v6_prefixes      = [for i in var.host_indices : cidrsubnet(var.dn42_v6_cidr, 64 - local.dn42_v6_prefix_length, i)]
  dn42_addresses_v6     = [for p in local.dn42_v6_prefixes : cidrhost(p, 1)]
  is_controller         = var.is_controller
}

output "host_indices" {
  value = var.host_indices
}
output "dn42_addresses_v4" {
  value = local.dn42_addresses_v4
}
output "dn42_v6_prefixes" {
  value = local.dn42_v6_prefixes
}
output "dn42_addresses_v6" {
  value = local.dn42_addresses_v6
}
output "enable_dn42" {
  value = var.enable_dn42
}
output "ike_port" {
  value = var.ike_port
}
output "nat_t_port" {
  value = var.nat_t_port
}
output "is_controller" {
  value = local.is_controller
}
