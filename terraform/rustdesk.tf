resource "tls_private_key" "rustdesk_server" {
  algorithm = "ED25519"

  lifecycle {
    prevent_destroy = true
  }
}

resource "random_password" "rustdesk_api_jwt_key" {
  length  = 64
  special = false
}

output "rustdesk_server_key" {
  value       = tls_private_key.rustdesk_server.private_key_pem
  sensitive   = true
  description = "RustDesk ID server identity, extracted only to fra0 SOPS; convert to libsodium format at runtime."
}

output "rustdesk_server_public_key" {
  value       = tls_private_key.rustdesk_server.public_key_openssh
  description = "Public-only RustDesk relay credential; the runtime helper converts OpenSSH to the client base64 form."
}
