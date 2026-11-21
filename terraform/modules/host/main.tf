variable "name" {
  type = string
}


variable "rustdesk_server_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "rustdesk_api_jwt_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "rustdesk_server_public_key" {
  type    = string
  default = null
}

output "rustdesk_server_public_key" {
  value = var.rustdesk_server_public_key
}

output "rustdesk_api_jwt_key" {
  value     = var.rustdesk_api_jwt_key
  sensitive = true
}

output "rustdesk_server_key" {
  value     = var.rustdesk_server_key
  sensitive = true
}
