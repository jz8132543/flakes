locals {
  hosts = {
    nue0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "185.216.178.70"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2a03:4000:4f:92d::"
        }
      }
      ddns_records = {}
      host_indices = [3]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    tyo1 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "216.23.85.218"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2a13:edc0:24:1d5::a"
        }
      }
      ddns_records = {}
      host_indices = [4]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    tyo0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "45.66.129.234"
        }
      }
      ddns_records = {}
      host_indices = [5]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    hkg4 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "123.254.105.134"
        }
      }
      ddns_records = {}
      host_indices = [9]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    hkg5 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "216.23.92.172"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2401:2660:1:9b::a"
        }
      }
      ddns_records = {}
      host_indices = [7]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    isk = {
      records = {}
      ddns_records = {
        a = {
          proxied = false
          type    = "A"
          value   = "127.0.0.1"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "::1"
        }
      }
      host_indices = [8]
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
    arx8 = {
      records = {}
      ddns_records = {
        a = {
          proxied = false
          type    = "A"
          value   = "127.0.0.1"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "::1"
        }
      }
      host_indices = [31]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    cu = {
      records      = {}
      ddns_records = {}
      host_indices = [6]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    can0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "8.138.123.219"
        }
      }
      ddns_records = {}
      host_indices = [11]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    can1 = {
      records      = {}
      ddns_records = {}
      host_indices = [12]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    can2 = {
      records      = {}
      ddns_records = {}
      host_indices = [13]
      endpoints_v4 = []
      endpoints_v6 = []
    }
    sjc0 = {
      records = {
        a = {
          proxied = false
          type    = "A"
          value   = "45.143.130.241"
        }
        aaaa = {
          proxied = false
          type    = "AAAA"
          value   = "2604:a840:100:2e9::a"
        }
      }
      ddns_records = {}
      host_indices = [16]
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

  name                 = each.key
  cloudflare_zone_id   = cloudflare_zone.im_dora.id
  cloudflare_zone_name = cloudflare_zone.im_dora.name
  records              = each.value.records
  ddns_records         = each.value.ddns_records
  host_indices         = each.value.host_indices
  dn42_v4_cidr         = var.dn42_v4_cidr
  dn42_v6_cidr         = var.dn42_v6_cidr
  endpoints_v4         = each.value.endpoints_v4
  endpoints_v6         = each.value.endpoints_v6
}

output "hosts" {
  value     = module.hosts
  sensitive = true
}
