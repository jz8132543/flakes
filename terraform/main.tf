variable "zotero_bucket_name" {
  description = "Globally unique, private B2 bucket name for Zotero WebDAV/S3 attachments."
  type        = string
  default     = "replace-with-your-zotero-bucket"
}

resource "b2_bucket" "zotero_attachments" {
  bucket_name = var.zotero_bucket_name
  bucket_type = "allPrivate"

  lifecycle_rules {
    file_name_prefix              = ""
    days_from_uploading_to_hiding = null
    days_from_hiding_to_deleting  = 30
  }
}

resource "b2_application_key" "zotero_attachments" {
  key_name  = "zotero-attachments"
  bucket_id = b2_bucket.zotero_attachments.id
  capabilities = [
    "deleteFiles",
    "listFiles",
    "readFiles",
    "writeFiles"
  ]
}

output "zotero_bucket_name" { value = b2_bucket.zotero_attachments.bucket_name }
output "zotero_application_key_id" { value = b2_application_key.zotero_attachments.application_key_id }
output "zotero_application_key" {
  value     = b2_application_key.zotero_attachments.application_key
  sensitive = true
}
