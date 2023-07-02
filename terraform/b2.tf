provider "b2" {
  application_key_id = data.sops_file.terraform.data["b2.application-key-id"]
  application_key    = data.sops_file.terraform.data["b2.application-key"]
}

data "b2_account_info" "main" {
}

output "b2_s3_api_url" {
  value = data.b2_account_info.main.s3_api_url
}
output "b2_download_url" {
  value = data.b2_account_info.main.download_url
}
module "b2_s3_api_url" {
  source = "matti/urlparse/external"
  url    = data.b2_account_info.main.s3_api_url
}
module "b2_download_url" {
  source = "matti/urlparse/external"
  url    = data.b2_account_info.main.download_url
}
output "b2_s3_api_host" {
  value = module.b2_s3_api_url.host
}
output "b2_s3_region" {
  value = regex("^s3.([a-z0-9\\-]+).backblazeb2.com$", module.b2_s3_api_url.host)[0]
}

resource "b2_bucket" "synapse_media" {
  bucket_name = "doraim-synapse-media"
  bucket_type = "allPrivate"

  # keep only the last version of the file
  lifecycle_rules {
    file_name_prefix              = ""
    days_from_uploading_to_hiding = null
    days_from_hiding_to_deleting  = 1
  }
}
resource "b2_application_key" "synapse_media" {
  key_name  = "synapse-media"
  bucket_id = b2_bucket.synapse_media.id
  capabilities = [
    "deleteFiles",
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readBucketEncryption",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeBucketEncryption",
    "writeFiles"
  ]
}
output "b2_synapse_media_bucket_name" {
  value     = b2_bucket.synapse_media.bucket_name
  sensitive = false
}
output "b2_synapse_media_key_id" {
  value     = b2_application_key.synapse_media.application_key_id
  sensitive = false
}
output "b2_synapse_media_access_key" {
  value     = b2_application_key.synapse_media.application_key
  sensitive = true
}

# mastodon
resource "b2_bucket" "mastodon_media" {
  bucket_name = "doraim-mastodon-media"
  bucket_type = "allPublic"

  # keep only the last version of the file
  lifecycle_rules {
    file_name_prefix              = ""
    days_from_uploading_to_hiding = null
    days_from_hiding_to_deleting  = 1
  }

  cors_rules {
    cors_rule_name = "allow-media-on-dora-im"
    allowed_operations = [
      "s3_head",
      "b2_download_file_by_id",
      "b2_download_file_by_name",
      "s3_get"
    ]
    allowed_origins = [
      "https://*.dora.im"
    ]
    max_age_seconds = 86400
  }
}
resource "b2_application_key" "mastodon_media" {
  key_name  = "mastodon-media"
  bucket_id = b2_bucket.mastodon_media.id
  capabilities = [
    "deleteFiles",
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readBucketEncryption",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeBucketEncryption",
    "writeFiles"
  ]
}
output "b2_mastodon_media_bucket_name" {
  value     = b2_bucket.mastodon_media.bucket_name
  sensitive = false
}
output "b2_mastodon_media_key_id" {
  value     = b2_application_key.mastodon_media.application_key_id
  sensitive = false
}
output "b2_mastodon_media_access_key" {
  value     = b2_application_key.mastodon_media.application_key
  sensitive = true
}
