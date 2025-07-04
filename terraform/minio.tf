provider "minio" {
  minio_server   = "minio.dora.im"
  minio_user     = data.sops_file.terraform.data["minio.root.user"]
  minio_password = data.sops_file.terraform.data["minio.root.password"]
  minio_ssl      = true
}

# Pastebin

# resource "minio_s3_bucket" "pastebin" {
#   bucket = "pastebin"
#   acl    = "private"
#   quota  = 1 * 1024 * 1024 * 1024 # in bytes, 1 GiB
# }
#
# resource "minio_iam_user" "pastebin" {
#   name = "pastebin"
# }
#
# output "minio_pastebin_key_id" {
#   value     = minio_iam_user.pastebin.id
#   sensitive = false
# }
# output "minio_pastebin_access_key" {
#   value     = minio_iam_user.pastebin.secret
#   sensitive = true
# }
#
# data "minio_iam_policy_document" "pastebin" {
#   statement {
#     actions = [
#       "s3:*",
#     ]
#     resources = [
#       "arn:aws:s3:::pastebin/*",
#     ]
#   }
# }
#
# resource "minio_iam_policy" "pastebin" {
#   name   = "pastebin"
#   policy = data.minio_iam_policy_document.pastebin.json
# }
#
# resource "minio_iam_user_policy_attachment" "pastebin" {
#   policy_name = minio_iam_policy.pastebin.name
#   user_name   = minio_iam_user.pastebin.name
# }
#
# resource "minio_ilm_policy" "pastebin_expire_1d" {
#   bucket = minio_s3_bucket.pastebin.bucket
#
#   rule {
#     id         = "expire-7d"
#     expiration = "7d"
#   }
# }
