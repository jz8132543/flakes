variable "dn42_v4_cidr" {
  default = "172.20.232.0/26"
  type    = string
}
variable "dn42_v6_cidr" {
  default = "fd53:90fd:4bb6::/48"
  type    = string
}
output "dn42_v4_cidr" {
  value     = var.dn42_v4_cidr
  sensitive = false
}
output "dn42_v6_cidr" {
  value     = var.dn42_v6_cidr
  sensitive = false
}
