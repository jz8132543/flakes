provider "cloudflare" {
  api_token = data.sops_file.terraform.data["cloudflare.api-token"]
}

# -------------
# DDNS and ACME token

# data "cloudflare_api_token_permission_groups" "all" {}
#
# resource "cloudflare_api_token" "ddns" {
#   name = "ddns-acme"
#
#   policy {
#     permission_groups = [
#       data.cloudflare_api_token_permission_groups.all.zone["Zone Read"],
#       data.cloudflare_api_token_permission_groups.all.zone["Zone Settings Read"],
#       data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
#     ]
#     resources = {
#       "com.cloudflare.api.account.zone.*" = "*"
#     }
#   }
# }
#
# output "cloudflare_token" {
#   value     = cloudflare_api_token.ddns.value
#   sensitive = true
# }

# -------------
# Account ID

locals {
  cloudflare_main_account_id = data.sops_file.terraform.data["cloudflare.account-id"]
}

# -------------
# Zones

resource "cloudflare_zone" "im_dora" {
  account_id = local.cloudflare_main_account_id
  zone       = "dora.im"
}

resource "cloudflare_zone_settings_override" "im_dora" {
  zone_id = cloudflare_zone.im_dora.id
  settings {
    ssl = "strict"
  }
}

# ttl = 1 for automatic

# CNAME records

resource "cloudflare_record" "im_dora" {
  name    = "shg0"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "home.sots.eu.org"
  zone_id = cloudflare_zone.im_dora.id
}

locals {
  service_cname_mappings = {
    headscale = { on = "fra0", proxy = false }
    cache     = { on = "fra0", proxy = false }
    hydra     = { on = "fra0", proxy = false }
    mail      = { on = "fra0", proxy = false }

    m         = { on = "fra1", proxy = true }
    zone      = { on = "fra1", proxy = true }
    "admin.m" = { on = "fra1", proxy = true }
    sso       = { on = "fra1", proxy = true }
    vault     = { on = "fra1", proxy = true }
    box       = { on = "fra1", proxy = true }
    searx     = { on = "ams0", proxy = false }
    morty     = { on = "ams0", proxy = false }
    ldap      = { on = "fra1", proxy = false }
    mta-sts   = { on = "fra1", proxy = false }

    minio         = { on = "dfw2", proxy = false }
    minio-console = { on = "dfw2", proxy = false }

  }
}
output "service_cname_mappings" {
  value     = local.service_cname_mappings
  sensitive = false
}

resource "cloudflare_record" "general_cname" {
  for_each = local.service_cname_mappings

  name    = each.key
  proxied = each.value.proxy
  ttl     = 1
  type    = "CNAME"
  value   = "${each.value.on}.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# ROOT record
resource "cloudflare_record" "dora" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "fra1.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# b2
resource "cloudflare_record" "dora_b2" {
  name    = "b2"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  value   = module.b2_download_url.host
  zone_id = cloudflare_zone.im_dora.id
}

# matrix SRV record
resource "cloudflare_record" "_matrix_tcp" {
  name    = "_matrix._tcp"
  type    = "SRV"
  zone_id = cloudflare_zone.im_dora.id
  data {
    service  = "_matrix"
    proto    = "_tcp"
    name     = cloudflare_zone.im_dora.zone
    priority = 10
    weight   = 5
    port     = 443
    target   = "m.dora.im"
  }
}

# mail

resource "cloudflare_record" "dora_dkim" {
  name    = "default._domainkey"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzuafKXbacHeSP/2YgMN9YntpX3e5OhU+48qRliq3HDiQu6yDoEF7jVrXsK6MPgFggv7qRG+DdGGAn6Ucwjb89RESnFSujLsrhyZO6GhGcuF8brp/VSJxSBTrdoz1IQQtBjSWjREeT1wITP7Pktol4jMvXc//FBBcSKJ85aNWxLfT3L+lJII+hAPShlaB8AsUGnu2I/l1ec6/Eet5RSqI2jnmsx2qKxGOhyc0FfrYZFdnSRDDxUNvbNZuTM8nGTmDm1YWLFBHr8Ugjju4cyXFm61ifDpXcFRed2Bb6tEW8m8a1tLkpQySF1REPvtgk0YCZ+2CbHZSQA5V0X1VfjEA2QIDAQAB"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_dmarc" {
  name    = "_dmarc"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=DMARC1; p=quarantine; ruf=mailto:i@dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_spf" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=spf1 mx mx:dora.im -all"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_mta_sts" {
  name    = "_mta-sts"
  proxied = false
  ttl     = 1
  type    = "TXT"
  value   = "v=STSv1; id=2022621T010102"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_mx_fra0" {
  name     = "dora.im"
  proxied  = false
  ttl      = 1
  type     = "MX"
  value    = "fra0.dora.im"
  priority = 1
  zone_id  = cloudflare_zone.im_dora.id
}

# Machines

resource "cloudflare_record" "dora_postgres" {
  name    = "postgres"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "100.64.0.8"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_tippy" {
  name    = "tippy"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "82.156.22.240"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo0" {
  name    = "tyo0"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "45.66.129.234"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax0" {
  name    = "lax0"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "23.234.207.154"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax2" {
  name    = "lax2"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "198.52.97.195"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_nue0" {
  name    = "nue0"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "45.142.176.126"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo1" {
  name    = "tyo1"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "43.207.199.230"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo3" {
  name    = "tyo3"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "194.87.169.90"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg0" {
  name    = "hkg0"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "20.187.90.38"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg3" {
  name    = "hkg3"
  proxied = false
  ttl     = 1
  type    = "A"
  value   = "45.67.200.54"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg2" {
  name    = "hkg2"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "chuyv.eastasia.cloudapp.azure.com"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_icn0" {
  name    = "icn0"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  value   = "kr.onlynull.live"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg3_v6" {
  name    = "hkg3"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  value   = "2a0e:aa07:4000::1:cd9b:d26"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax0_v6" {
  name    = "lax0"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  value   = "2607:f130:0:ea:ff:ff:3a2c:61e0"
  zone_id = cloudflare_zone.im_dora.id
}
