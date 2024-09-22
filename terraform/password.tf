provider "htpasswd" {
}
resource "random_password" "ntfy_sh_topic_secret" {
  length  = 32
  upper   = false
  special = false
}
output "ntfy_sh_topic_secret" {
  value     = random_password.ntfy_sh_topic_secret.result
  sensitive = true
}
