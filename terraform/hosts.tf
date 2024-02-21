locals {
  hosts = {
    fra0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "109.71.253.195"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2a0e:6a80:3:1e3::"
        }
      }
      ddns_records = {}
      host_indices = [1]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    ams0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "212.50.247.48"
        }
      }
      ddns_records = {}
      host_indices = [3]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    dfw0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "154.9.225.139"
        }
      }
      ddns_records = {}
      host_indices = [4]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    dfw1 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "172.99.148.201"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2606:fc40:0:b38::1"
        }
      }
      ddns_records = {}
      host_indices = [5]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    surface = {
      records      = {}
      ddns_records = {}
      host_indices = [30]
      endpoints_v4 = []
      endpoints_v6 = []
    }
  }
}

locals {
  all_host_indices = flatten([for name, cfg in local.hosts : cfg.host_indices])
}

data "assert_test" "host_indices_collision" {
  test  = length(local.all_host_indices) == length(toset(local.all_host_indices))
  throw = "host indices collision"
}

module "hosts" {
  source = "./modules/host"

  for_each = {
    for index, host_name in keys(local.hosts) :
    host_name => merge(
      { index = index },
      local.hosts[host_name]
    )
  }

  name               = each.key
  cloudflare_zone_id = cloudflare_zone.im_dora.id
  records            = each.value.records
  ddns_records       = each.value.ddns_records
  host_indices       = each.value.host_indices
  dn42_v4_cidr       = var.dn42_v4_cidr
  dn42_v6_cidr       = var.dn42_v6_cidr
  endpoints_v4       = each.value.endpoints_v4
  endpoints_v6       = each.value.endpoints_v6
}

output "hosts" {
  value     = module.hosts
  sensitive = true
}
