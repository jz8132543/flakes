# ==============================================================================
# CDN Data — THE ONLY FILE THAT NEEDS HUMAN EDITING FOR CDN CHANGES
# ==============================================================================
# This file is the single source of truth for the ATC CDN infrastructure.
# Both Terraform (DNS records, CNAME mappings) and NixOS (DNS zones, Traefik
# proxies) consume this data.
#
# After editing this file:
#   1. Run: make cdn-data          → regenerates nixos/modules/services/atc/data.json
#   2. Run: terraform plan/apply   → updates Cloudflare DNS records
#   3. Deploy NixOS hosts          → picks up the new data.json
#
# To add a new CDN-accelerated service (e.g. "newapp" served by fra0):
#   a) Add `newapp = "fra0"` to cdn_services below.
#   b) Run the three steps above.
#   No other files need to change.
# ==============================================================================

locals {
  # ── Router hosts ─────────────────────────────────────────────────────────
  # The machines that run CoreDNS and act as authoritative NS for cdn.<domain>.
  # Must be names present in cdn_edge_nodes below.
  cdn_router_hosts = ["fra0"]

  # ── Edge nodes ───────────────────────────────────────────────────────────
  # Fields:
  #   name   – short hostname (matches networking.hostName on that machine)
  #   ipv4   – public IPv4 (required)
  #   ipv6   – public IPv6 (null if absent)
  #   region – geographic tag (AP / HK / EU / US)
  #   weight – relative weight for round-robin DNS (higher = more traffic)
  #            Weight is implemented by repeating the IP in DNS responses.
  #            A node with weight=2 gets ~2x more queries than weight=1.
  cdn_edge_nodes = [
    {
      name   = "tyo0"
      ipv4   = "45.66.130.158"
      ipv6   = null
      region = "AP"
      weight = 1
    },
    {
      name   = "tyo1"
      ipv4   = "216.23.85.218"
      ipv6   = null
      region = "AP"
      weight = 1
    },
    {
      name   = "hkg5"
      ipv4   = "216.23.94.148"
      ipv6   = null
      region = "HK"
      weight = 1
    },
    {
      name   = "sjc0"
      ipv4   = "45.143.130.230"
      ipv6   = null
      region = "US"
      weight = 1
    },
    {
      name   = "nue0"
      ipv4   = "185.216.178.70"
      ipv6   = "2a03:4000:4f:92d::"
      region = "EU"
      weight = 1
    },
    {
      name   = "fra0"
      ipv4   = "23.165.200.135"
      ipv6   = null
      region = "EU"
      weight = 1
    },
  ]

  # ── Services ─────────────────────────────────────────────────────────────
  # service-label → upstream-origin-hostname mapping.
  # The label is used as the subdomain: <label>.dora.im
  # The origin is the hostname of the compute node that actually runs the app.
  cdn_services = {
    jellyfin = "nue0"
    zone     = "fra0"
    alist    = "fra0"
    office   = "fra0"
    code     = "fra0"
    cloud    = "fra0"
    api      = "fra0"
    cpa      = "fra0"
    m        = "fra0"
    chat     = "fra0"
    cache    = "fra0"
    s        = "fra0"
  }

  # ── Terraform-usable derived values ──────────────────────────────────────
  # Map from edge node name to its properties (for for_each in resources).
  cdn_edge_nodes_map = {
    for n in local.cdn_edge_nodes : n.name => n
  }

  # Router node objects (subset of edge nodes).
  cdn_router_nodes = [
    for n in local.cdn_edge_nodes : n
    if contains(local.cdn_router_hosts, n.name)
  ]
}

# Output the full dataset so `terraform output -json cdn_data` can be consumed
# by `make cdn-data` to regenerate data.json for NixOS modules.
output "cdn_data" {
  description = "Full CDN dataset consumed by NixOS ATC modules (via make cdn-data)"
  sensitive   = false
  value = {
    routerHosts = local.cdn_router_hosts
    edgeNodes   = local.cdn_edge_nodes
    services    = local.cdn_services
  }
}

# ==============================================================================
# Cloudflare DNS records derived from the data above
# ==============================================================================

# ── NS delegation for cdn.<domain> ───────────────────────────────────────────
# cdn.dora.im is delegated directly to the router hosts (nue0.dora.im,
# fra0.dora.im). Using existing fully-qualified hostnames as NS targets avoids
# the need for ns1/ns2 intermediaries. The parent zone (dora.im) already has
# (or will have) A records for these hostnames, so no separate glue is needed
# inside cdn.dora.im.
resource "cloudflare_dns_record" "cdn_ns" {
  for_each = toset(local.cdn_router_hosts)

  name    = "cdn.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 3600
  type    = "NS"
  content = "${each.value}.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

# ── A/AAAA records for router hosts in the parent zone ───────────────────────
# These records allow resolvers to find our NS hosts. They live in dora.im
# (parent), not in cdn.dora.im (delegated), so Cloudflare manages them.
resource "cloudflare_dns_record" "cdn_router_a" {
  for_each = {
    for n in local.cdn_router_nodes : n.name => n
  }

  name    = "${each.value.name}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 3600
  type    = "A"
  content = each.value.ipv4
  zone_id = cloudflare_zone.im_dora.id
}

resource "cloudflare_dns_record" "cdn_router_aaaa" {
  for_each = {
    for n in local.cdn_router_nodes : n.name => n
    if n.ipv6 != null
  }

  name    = "${each.value.name}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 3600
  type    = "AAAA"
  content = each.value.ipv6
  zone_id = cloudflare_zone.im_dora.id
}

# ── CNAME records for CDN-accelerated services ────────────────────────────────
# Each service label in cdn_services gets a CNAME:
#   <label>.dora.im → <label>.cdn.dora.im
# The cdn.dora.im authoritative server then answers with the edge pool IPs.
resource "cloudflare_dns_record" "cdn_service_cname" {
  for_each = local.cdn_services

  name    = "${each.key}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1 # automatic
  type    = "CNAME"
  content = "${each.key}.cdn.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}
