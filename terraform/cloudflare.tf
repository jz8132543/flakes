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
  name = "dora.im"
  type = "full"
  account = {
    id = local.cloudflare_main_account_id
  }
}

resource "cloudflare_zone_setting" "im_dora" {
  zone_id    = cloudflare_zone.im_dora.id
  setting_id = "ssl"
  value      = "strict"
}

# ttl = 1 for automatic

# CNAME records

resource "cloudflare_dns_record" "dora_shg0" {
  name    = "shg0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "home.sots.eu.org"
  zone_id = cloudflare_zone.im_dora.id
}

locals {
  service_cname_mappings = {
    vault         = { on = "nue0", proxy = false }
    ts            = { on = "nue0", proxy = false }
    ldap          = { on = "nue0", proxy = false }
    sso           = { on = "nue0", proxy = false }
    mta-sts       = { on = "nue0", proxy = false }
    atuin         = { on = "nue0", proxy = false }
    ntfy          = { on = "nue0", proxy = false }
    pb            = { on = "nue0", proxy = false }
    ollama        = { on = "nue0", proxy = false }
    ollama-ui     = { on = "nue0", proxy = false }
    minio         = { on = "nue0", proxy = false }
    minio-console = { on = "nue0", proxy = false }
    "admin.m"     = { on = "nue0", proxy = false }
    zone          = { on = "nue0", proxy = false }
    jellyfin      = { on = "nue0", proxy = false }
    alist         = { on = "nue0", proxy = false }
    office        = { on = "nue0", proxy = false }
    code          = { on = "nue0", proxy = false }
    cloud         = { on = "nue0", proxy = false }
    reader        = { on = "nue0", proxy = false }
    plex          = { on = "nue0", proxy = false }
    dash          = { on = "nue0", proxy = false }
    metrics       = { on = "nue0", proxy = false }
    tv            = { on = "nue0", proxy = false }
    cookiecloud   = { on = "nue0", proxy = false }
    dash          = { on = "nue0", proxy = false }
    cookie        = { on = "nue0", proxy = false }
    home          = { on = "nue0", proxy = false }
    link          = { on = "nue0", proxy = false }
    claw          = { on = "nue0", proxy = false }
    # prowlarr           = { on = "nue0", proxy = false }
    # radarr             = { on = "nue0", proxy = false }
    # bazarr             = { on = "nue0", proxy = false }
    # qbit               = { on = "nue0", proxy = false }
    searx              = { on = "hkg4", proxy = false }
    murmur             = { on = "hkg4", proxy = false }
    p                  = { on = "hkg4", proxy = false }
    perplexica-backend = { on = "hkg4", proxy = false }
  }
}
output "service_cname_mappings" {
  value     = local.service_cname_mappings
  sensitive = false
}

resource "cloudflare_dns_record" "general_cname" {
  for_each = local.service_cname_mappings

  name    = "${each.key}.${cloudflare_zone.im_dora.name}"
  proxied = each.value.proxy
  ttl     = 1
  type    = "CNAME"
  content = "${each.value.on}.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# ROOT record
resource "cloudflare_dns_record" "dora" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "nue0.dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

# b2
# resource "cloudflare_dns_record" "dora_b2" {
#   name    = "b2.${cloudflare_zone.im_dora.name}"
#   proxied = true
#   ttl     = 1
#   type    = "CNAME"
#   content = module.b2_download_url.host
#   zone_id = cloudflare_zone.im_dora.id
# }

# matrix SRV records
resource "cloudflare_dns_record" "_matrix_tcp" {
  name    = "_matrix._tcp.${cloudflare_zone.im_dora.name}"
  type    = "SRV"
  ttl     = 1
  zone_id = cloudflare_zone.im_dora.id
  data = {
    priority = 10
    weight   = 5
    port     = 443
    target   = "m.dora.im"
  }
}

resource "cloudflare_dns_record" "_turn_udp" {
  name    = "_turn._udp.${cloudflare_zone.im_dora.name}"
  type    = "SRV"
  ttl     = 1
  zone_id = cloudflare_zone.im_dora.id
  data = {
    priority = 10
    weight   = 5
    port     = 3478
    target   = "nue0.dora.im"
  }
}

resource "cloudflare_dns_record" "_turns_udp" {
  name    = "_turns._udp.${cloudflare_zone.im_dora.name}"
  type    = "SRV"
  ttl     = 1
  zone_id = cloudflare_zone.im_dora.id
  data = {
    priority = 10
    weight   = 5
    port     = 5349
    target   = "nue0.dora.im"
  }
}

resource "cloudflare_dns_record" "_turn_tcp" {
  name    = "_turn._tcp.${cloudflare_zone.im_dora.name}"
  type    = "SRV"
  ttl     = 1
  zone_id = cloudflare_zone.im_dora.id
  data = {
    priority = 10
    weight   = 5
    port     = 3478
    target   = "nue0.dora.im"
  }
}

resource "cloudflare_dns_record" "_turns_tcp" {
  name    = "_turns._tcp.${cloudflare_zone.im_dora.name}"
  type    = "SRV"
  ttl     = 1
  zone_id = cloudflare_zone.im_dora.id
  data = {
    priority = 10
    weight   = 5
    port     = 5349
    target   = "nue0.dora.im"
  }
}

# mail

resource "cloudflare_dns_record" "mail" {
  name    = "mail.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "glacier.mxrouting.net"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_dkim" {
  name    = "x._domainkey.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=DKIM1;k=rsa;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnsLpb6J3ymivQlMqzN4oKAxPNYWNpRvD8uM1e4lWlgl+jYl2lDEzB5nIewbH9HnQ6aWi0HVgku6jqllOR2Fqspc/DkSERA1gPeqfelP3V5+ligKNU8PG26G8X+9ibR11oG9Iz1bEXBJ6ws4aSADl+e5uCS3jzJydPxJEdYERXVQA0CiSi3FK3BWlUD3dxmE80qZwYW+pxqobO4gyozow8/C8sz19zy5igJLdM5TfhTaOC1mXxL33tSJwAPlpp8homAmMX0uecIVv/JUxs4ucgu6swMjYRSeuruq1e6APTi+f+0wvnZNEegB5xTvm7IcQ0z75wA+Uw6VE/4iFuov3lQIDAQAB"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_dns_record" "dora_dmarc" {
  name    = "_dmarc.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=DMARC1; p=quarantine; ruf=mailto:i@dora.im"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_dns_record" "dora_spf" {
  name    = "dora.im"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=spf1 include:mxlogin.com -all"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_dns_record" "dora_mta_sts" {
  name    = "_mta-sts.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "TXT"
  content = "v=STSv1; id=20241201T010102"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_mx_mxroute1" {
  name     = "dora.im"
  proxied  = false
  ttl      = 1
  type     = "MX"
  content  = "glacier.mxrouting.net"
  priority = 10
  zone_id  = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_mx_mxroute2" {
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
resource "cloudflare_dns_record" "dora_matrix" {
  name    = "m.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "185.216.178.70"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_matrix_v6" {
  name    = "m.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2a03:4000:4f:92d::"
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_dns_record" "dora_tyo0" {
  name    = "tyo0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "45.66.129.234"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_lax0" {
  name    = "lax0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "74.48.188.251"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_lax2" {
  name    = "lax2.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "74.48.170.226"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_tyo1" {
  name    = "tyo1.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "54.248.91.93"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_tyo3" {
  name    = "tyo3.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "194.87.169.90"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_hkg0" {
  name    = "hkg0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "20.187.90.38"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_hkg3" {
  name    = "hkg3.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "45.67.200.54"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_hkg2" {
  name    = "hkg2.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "chuyv.eastasia.cloudapp.azure.com"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_icn0" {
  name    = "icn0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "kr.onlynull.live"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_hkg3_v6" {
  name    = "hkg3.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2a0e:aa07:4000::1:cd9b:d26"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_lax0_v6" {
  name    = "lax0.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2607:f130:0:ea:ff:ff:3a2c:61e0"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_fra2" {
  name    = "fra2.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "A"
  content = "23.165.200.135"
  zone_id = cloudflare_zone.im_dora.id
}
# 酷雪云
resource "cloudflare_dns_record" "dora_cuv6" {
  name    = "cuv6.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2408:8207:25b1:2701:6666:16:3efc:9adf"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_cmv6" {
  name    = "cmv6.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "AAAA"
  content = "2409:8a00:2640:4e01:6666:16:3efc:9adf"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_cu" {
  name    = "cu.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "fastu.kxy.ovh"
  zone_id = cloudflare_zone.im_dora.id
}
resource "cloudflare_dns_record" "dora_cm" {
  name    = "cm.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "fastm.kxy.ovh"
  zone_id = cloudflare_zone.im_dora.id
}
