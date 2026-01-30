# Media stack automation using devopsarr terraform providers
# Automates: Sonarr, Radarr, Prowlarr configuration
# NixOS auto-config modules handle: Jellyfin, Jellyseerr, Bazarr, qBittorrent
#
# Home Theater System Configuration:
# - Username: i
# - Password: from sops "password"
# - Email: noreply@dora.im
# - SMTP Password: from sops "smtp/password"

locals {
  media_domain = "dora.im"

  # External URLs for terraform access (via Traefik)
  sonarr_url   = "https://sonarr.dora.im"
  radarr_url   = "https://radarr.dora.im"
  prowlarr_url = "https://prowlarr.dora.im"

  # Internal URLs for service-to-service communication on nue0
  sonarr_internal   = "http://127.0.0.1:8989"
  radarr_internal   = "http://127.0.0.1:7878"
  prowlarr_internal = "http://127.0.0.1:9696"
  qbit_internal     = "http://127.0.0.1:8080"

  # SMTP settings (using noreply@dora.im as sender)
  smtp_server   = "mail.mxlogin.com"
  smtp_port     = 587
  smtp_from     = "noreply@dora.im"
  smtp_username = "noreply@dora.im"
  smtp_password = data.sops_file.common.data["smtp/password"]

  # Notification recipient
  notification_email = "i@dora.im"

  # Common credentials
  media_username = "i"
  media_password = data.sops_file.common.data["password"]
}

# =============================================================================
# Providers configuration
# =============================================================================

provider "sonarr" {
  url     = local.sonarr_url
  api_key = data.sops_file.common.data["media.sonarr_api_key"]
}

provider "radarr" {
  url     = local.radarr_url
  api_key = data.sops_file.common.data["media.radarr_api_key"]
}

provider "prowlarr" {
  url     = local.prowlarr_url
  api_key = data.sops_file.common.data["media.prowlarr_api_key"]
}

# =============================================================================
# Sonarr configuration
# =============================================================================

# Root folder for TV shows
resource "sonarr_root_folder" "tv" {
  path = "/srv/media/tv"
}

# Naming convention (following TRaSH Guides)
resource "sonarr_naming" "default" {
  rename_episodes            = true
  replace_illegal_characters = true
  multi_episode_style        = 5 # Prefixed Range
  colon_replacement_format   = 4 # Smart Replace

  standard_episode_format = "{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  daily_episode_format    = "{Series TitleYear} - {Air-Date} - {Episode CleanTitle} [{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  anime_episode_format    = "{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} [{Quality Full}]{[MediaInfo VideoDynamicRangeType]}[{MediaInfo VideoBitDepth}bit]{[MediaInfo VideoCodec]}[{Mediainfo AudioCodec} { Mediainfo AudioChannels}]{MediaInfo AudioLanguages}{-Release Group}"

  series_folder_format   = "{Series TitleYear} [tvdbid-{TvdbId}]"
  season_folder_format   = "Season {season:00}"
  specials_folder_format = "Specials"
}

# qBittorrent download client
resource "sonarr_download_client_qbittorrent" "qbit" {
  name     = "qBittorrent"
  enable   = true
  priority = 1
  host     = "127.0.0.1"
  port     = 8080

  tv_category                = "tv-sonarr"
  remove_completed_downloads = true
  remove_failed_downloads    = true
}

# Email notification for completed downloads
resource "sonarr_notification_email" "email" {
  name = "Email"

  on_grab                            = false
  on_download                        = true
  on_upgrade                         = true
  on_series_delete                   = false
  on_episode_file_delete             = false
  on_episode_file_delete_for_upgrade = false
  on_health_issue                    = true
  on_health_restored                 = true
  on_application_update              = false

  include_health_warnings = true

  server         = local.smtp_server
  port           = local.smtp_port
  from           = local.smtp_from
  to             = [local.notification_email]
  username       = local.smtp_username
  password       = local.smtp_password
  use_encryption = 1 # Always (STARTTLS)
}

# =============================================================================
# Radarr configuration
# =============================================================================

# Root folder for movies
resource "radarr_root_folder" "movies" {
  path = "/srv/media/movies"
}

# Naming convention (following TRaSH Guides)
resource "radarr_naming" "default" {
  rename_movies              = true
  replace_illegal_characters = true
  colon_replacement_format   = "smart"

  standard_movie_format = "{Movie CleanTitle} {(Release Year)} [imdbid-{ImdbId}] - {Edition Tags }{[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}"
  movie_folder_format   = "{Movie CleanTitle} ({Release Year}) [imdbid-{ImdbId}]"
}

# qBittorrent download client
resource "radarr_download_client_qbittorrent" "qbit" {
  name     = "qBittorrent"
  enable   = true
  priority = 1
  host     = "127.0.0.1"
  port     = 8080

  movie_category             = "movies-radarr"
  remove_completed_downloads = true
  remove_failed_downloads    = true
}

# Email notification
resource "radarr_notification_email" "email" {
  name = "Email"

  on_grab                          = false
  on_download                      = true
  on_upgrade                       = true
  on_movie_added                   = false
  on_movie_delete                  = false
  on_movie_file_delete             = false
  on_movie_file_delete_for_upgrade = false
  on_health_issue                  = true
  on_health_restored               = true
  on_application_update            = false

  include_health_warnings = true

  server         = local.smtp_server
  port           = local.smtp_port
  from           = local.smtp_from
  to             = [local.notification_email]
  username       = local.smtp_username
  password       = local.smtp_password
  use_encryption = 1 # Always (STARTTLS)
}

# =============================================================================
# Prowlarr configuration
# =============================================================================

# FlareSolverr proxy for Cloudflare-protected indexers
resource "prowlarr_indexer_proxy_flaresolverr" "flaresolverr" {
  name            = "FlareSolverr"
  host            = "http://127.0.0.1:8191"
  request_timeout = 60
}

# Connect Prowlarr to Sonarr
resource "prowlarr_application_sonarr" "sonarr" {
  name         = "Sonarr"
  sync_level   = "fullSync"
  base_url     = local.sonarr_internal
  prowlarr_url = local.prowlarr_internal
  api_key      = data.sops_file.common.data["media.sonarr_api_key"]

  sync_categories = [
    5000, # TV
    5010, # TV/WEB-DL
    5020, # TV/Foreign
    5030, # TV/SD
    5040, # TV/HD
    5045, # TV/UHD
    5050, # TV/Other
    5060, # TV/Sport
    5070, # TV/Anime
    5080, # TV/Documentary
  ]

  anime_sync_categories = [5070]
}

# Connect Prowlarr to Radarr
resource "prowlarr_application_radarr" "radarr" {
  name         = "Radarr"
  sync_level   = "fullSync"
  base_url     = local.radarr_internal
  prowlarr_url = local.prowlarr_internal
  api_key      = data.sops_file.common.data["media.radarr_api_key"]

  sync_categories = [
    2000, # Movies
    2010, # Movies/Foreign
    2020, # Movies/Other
    2030, # Movies/SD
    2040, # Movies/HD
    2045, # Movies/UHD
    2050, # Movies/BluRay
    2060, # Movies/3D
  ]
}

# qBittorrent download client for Prowlarr
resource "prowlarr_download_client_qbittorrent" "qbit" {
  name     = "qBittorrent"
  enable   = true
  priority = 1
  host     = "127.0.0.1"
  port     = 8080

  category = "prowlarr"
}

# =============================================================================
# Output useful information
# =============================================================================

output "media_stack_urls" {
  value = {
    jellyfin    = "https://jellyfin.dora.im"
    jellyseerr  = "https://seerr.dora.im"
    sonarr      = "https://sonarr.dora.im"
    radarr      = "https://radarr.dora.im"
    prowlarr    = "https://prowlarr.dora.im"
    bazarr      = "https://bazarr.dora.im"
    qbittorrent = "https://qbit.dora.im"
  }
  description = "URLs for media stack services"
}

output "media_credentials" {
  value = {
    username = "i"
    email    = "noreply@dora.im"
    note     = "Password is stored in sops secret 'password'"
  }
  description = "Credentials for media stack services"
}

output "media_config_notes" {
  value       = <<-EOT
    =========================================
    Home Theater System - Auto-Configuration
    =========================================
    
    All services are configured with:
    - Username: i
    - Password: (from sops secret 'password')
    - Email: noreply@dora.im
    - SMTP: noreply@dora.im (password from 'smtp/password')
    
    Service URLs:
    - Jellyfin:    https://jellyfin.dora.im
    - Jellyseerr:  https://seerr.dora.im  
    - Sonarr:      https://sonarr.dora.im
    - Radarr:      https://radarr.dora.im
    - Prowlarr:    https://prowlarr.dora.im
    - Bazarr:      https://bazarr.dora.im
    - qBittorrent: https://qbit.dora.im
    
    Auto-configured by NixOS:
    ✓ Jellyfin - Initial user created
    ✓ qBittorrent - Credentials and categories set
    ✓ Sonarr - Root folder and authentication
    ✓ Radarr - Root folder and authentication
    ✓ Prowlarr - Authentication enabled
    ✓ Bazarr - Connected to Sonarr/Radarr
    
    Configured by Terraform:
    ✓ Sonarr - Naming, download client, notifications
    ✓ Radarr - Naming, download client, notifications
    ✓ Prowlarr - FlareSolverr, app sync
    
    Manual steps (one-time):
    1. Jellyseerr - Complete setup wizard with Jellyfin login
    2. Prowlarr - Add indexers (torrent sites)
    3. Jellyfin - Add media libraries (Movies, TV Shows)
  EOT
  description = "Configuration notes and status"
}
