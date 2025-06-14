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

resource "cloudflare_record" "dora_shg0" {
  name    = "shg0"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "home.sots.eu.org"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_subscription" {
  name    = "subscription"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "cname.vercel-dns.com."
  zone_id = cloudflare_zone.im_dora.id
}

locals {
  service_cname_mappings = {
    vault              = { on = "fra1", proxy = false }
    ts                 = { on = "fra1", proxy = false }
    ldap               = { on = "fra1", proxy = false }
    sso                = { on = "fra1", proxy = false }
    mta-sts            = { on = "fra1", proxy = false }
    atuin              = { on = "fra1", proxy = false }
    ntfy               = { on = "fra1", proxy = false }
    pb                 = { on = "fra1", proxy = false }
    ollama             = { on = "fra1", proxy = false }
    ollama-ui          = { on = "fra1", proxy = false }
    minio              = { on = "fra1", proxy = false }
    minio-console      = { on = "fra1", proxy = false }
    "admin.m"          = { on = "fra1", proxy = false }
    jellyfin           = { on = "fra1", proxy = false }
    alist              = { on = "fra1", proxy = false }
    reader             = { on = "fra1", proxy = false }
    murmur             = { on = "hkg4", proxy = false }
    searx              = { on = "hkg4", proxy = false }
    morty              = { on = "hkg4", proxy = false }
    p                  = { on = "hkg4", proxy = false }
    perplexica-backend = { on = "hkg4", proxy = false }
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
  content = "${each.value.on}.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# ROOT record
resource "cloudflare_record" "dora" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "hkg4.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# b2
resource "cloudflare_record" "dora_b2" {
  name    = "b2"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  content = module.b2_download_url.host
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

resource "cloudflare_record" "mail" {
  name    = "mail"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "glacier.mxrouting.net"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_dkim" {
  name    = "x._domainkey"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=DKIM1;k=rsa;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnsLpb6J3ymivQlMqzN4oKAxPNYWNpRvD8uM1e4lWlgl+jYl2lDEzB5nIewbH9HnQ6aWi0HVgku6jqllOR2Fqspc/DkSERA1gPeqfelP3V5+ligKNU8PG26G8X+9ibR11oG9Iz1bEXBJ6ws4aSADl+e5uCS3jzJydPxJEdYERXVQA0CiSi3FK3BWlUD3dxmE80qZwYW+pxqobO4gyozow8/C8sz19zy5igJLdM5TfhTaOC1mXxL33tSJwAPlpp8homAmMX0uecIVv/JUxs4ucgu6swMjYRSeuruq1e6APTi+f+0wvnZNEegB5xTvm7IcQ0z75wA+Uw6VE/4iFuov3lQIDAQAB"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_dmarc" {
  name    = "_dmarc"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=DMARC1; p=quarantine; ruf=mailto:i@dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_spf" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=spf1 include:mxlogin.com -all"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_mta_sts" {
  name    = "_mta-sts"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=STSv1; id=20241201T010102"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_mx_mxroute1" {
  name     = "dora.im"
  proxied  = false
  ttl      = 1
  type     = "MX"
  content  = "glacier.mxrouting.net"
  priority = 10
  zone_id  = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_mx_mxroute2" {
  name     = "dora.im"
  proxied  = false
  ttl      = 1
  type     = "MX"
  content  = "glacier-relay.mxrouting.net"
  priority = 20
  zone_id  = cloudflare_zone.im_dora.id
}

# Machines

# RFC2782
resource "cloudflare_record" "dora_matrix" {
  name    = "m"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "176.116.18.242"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_matrix_v6" {
  name    = "m"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2a04:e8c0:18:619::"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_record" "dora_tippy" {
  name    = "tippy"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "82.156.22.240"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo0" {
  name    = "tyo0"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "45.66.129.234"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax0" {
  name    = "lax0"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "74.48.188.251"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax2" {
  name    = "lax2"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "74.48.170.226"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_nue0" {
  name    = "nue0"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "45.142.176.126"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo1" {
  name    = "tyo1"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "54.248.91.93"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_tyo3" {
  name    = "tyo3"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "194.87.169.90"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg0" {
  name    = "hkg0"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "20.187.90.38"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg3" {
  name    = "hkg3"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "45.67.200.54"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg2" {
  name    = "hkg2"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "chuyv.eastasia.cloudapp.azure.com"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_icn0" {
  name    = "icn0"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "kr.onlynull.live"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_hkg3_v6" {
  name    = "hkg3"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2a0e:aa07:4000::1:cd9b:d26"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_lax0_v6" {
  name    = "lax0"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2607:f130:0:ea:ff:ff:3a2c:61e0"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_record" "dora_fra2" {
  name    = "fra2"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "23.165.200.135"
  zone_id = cloudflare_zone.im_dora.id
}
