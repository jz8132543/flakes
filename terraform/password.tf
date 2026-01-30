provider "htpasswd" {
}

# =============================================================================
# Media Stack Password Generation
# =============================================================================

# qBittorrent password (will be stored in sops)
resource "random_password" "qbittorrent_password" {
  length  = 24
  special = false
}

# API keys for *arr services (32 char hex strings like the apps generate)
resource "random_password" "sonarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

resource "random_password" "radarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

resource "random_password" "prowlarr_api_key" {
  length  = 32
  special = false
  upper   = false
}

# Jellyfin OIDC client secret (if using SSO)
resource "random_password" "jellyfin_oidc_secret" {
  length  = 48
  special = false
}

# Autobrr secret
resource "random_password" "autobrr_secret" {
  length  = 48
  special = false
}

# =============================================================================
# Outputs for Media Stack
# =============================================================================

output "media_passwords" {
  value = {
    qbittorrent_password = random_password.qbittorrent_password.result
    sonarr_api_key       = random_password.sonarr_api_key.result
    radarr_api_key       = random_password.radarr_api_key.result
    prowlarr_api_key     = random_password.prowlarr_api_key.result
    jellyfin_oidc_secret = random_password.jellyfin_oidc_secret.result
    autobrr_secret       = random_password.autobrr_secret.result
  }
  sensitive   = true
  description = "Generated passwords for media stack services"
}

# =============================================================================
# Other Services
# =============================================================================

resource "random_password" "ntfy_sh_topic_secret" {
  length  = 32
  upper   = false
  special = false
}
output "ntfy_sh_topic_secret" {
  value     = random_password.ntfy_sh_topic_secret.result
  sensitive = true
}
