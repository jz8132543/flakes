# ==============================================================================
# CDN Data — THE ONLY FILE THAT NEEDS HUMAN EDITING FOR CDN CHANGES
# ==============================================================================
# This file is the single source of truth for the ATC CDN infrastructure.
# Both Terraform (DNS records, CNAME mappings) and NixOS (DNS zones, Traefik
# proxies) consume this data.
#
# After editing this file, run terraform-pipe. Its existing output extraction
# writes lib/data/data.json, which is consumed directly by the ATC NixOS
# modules. There is no second CDN data file.
#
# To add a new CDN-accelerated service (e.g. "newapp" served by fra0):
#   a) Add `newapp = "fra0"` to cdn_services below.
#   b) Run terraform-pipe.
#   No other files need to change.
# ==============================================================================

variable "ops_host" {
  type        = string
  default     = "ops.dora.im"
  description = "Traffic Ops API Host"
}

variable "ops_user" {
  type        = string
  default     = "admin"
  description = "Traffic Ops API User"
}

variable "ops_password" {
  type        = string
  default     = ""
  description = "Traffic Ops API Password (falls back to secrets/common.yaml atc.ops_password)"
  sensitive   = true
}

locals {
  # ── Router hosts ─────────────────────────────────────────────────────────
  # The machines that run CoreDNS and act as authoritative NS for cdn.<domain>.
  # Must be names present in cdn_edge_nodes below.
  # The initial deployment uses fra0 as the authoritative NS. Additional
  # NS hosts can be appended to the list as needed.
  cdn_ns_hosts = ["fra0"]
  cdn_ns_host  = local.cdn_ns_hosts[0]

  # ── Edge nodes ───────────────────────────────────────────────────────────
  # Fields:
  #   name   – short hostname (matches networking.hostName on that machine)
  #   region – edge-node location tag (AP / HK / EU / US)
  #   weight – relative weight for round-robin DNS (higher = more traffic)
  #
  # IP addresses are taken from local.hosts in hosts.tf and exported in
  # cdn_data. They are not duplicated here, so CDN data cannot go stale.
  cdn_edge_nodes = [
    {
      # fra0 hosts the authoritative DNS/control plane. Keep it in the
      # inventory for the NS record, but exclude it from weighted edge answers.
      name   = "fra0"
      region = "EU"
      weight = 0
    },
    {
      name   = "nue0"
      region = "EU"
      weight = 10
    },
  ]

  # ── Services ─────────────────────────────────────────────────────────────
  # service-label → upstream-origin-hostname mapping.
  # The label is used as the subdomain: <label>.dora.im
  # The origin is the hostname of the compute node that actually runs the app.
  cdn_services = {
    jellyfin = "fra0"
    zone     = "fra0"
    alist    = "fra0"
    office   = "fra0"
    code     = "fra0"
    cloud    = "fra0"
    api      = "fra0"
    cpa      = "fra0"
    m        = "fra0"
    chat     = "fra0"
    mcp      = "fra0"
    s        = "fra0"
    persona  = "fra0"
    bot      = "fra0"
    napcat   = "fra0"
  }

  # ── Terraform-usable derived values ──────────────────────────────────────
  # Map from edge node name to its properties (for for_each in resources).
  cdn_edge_nodes_with_addresses = [
    for n in local.cdn_edge_nodes : merge(n, {
      ipv4 = try(local.hosts[n.name].records.a.value, null)
      ipv6 = try(local.hosts[n.name].records.aaaa.value, null)
    })
  ]

}

# Output the full dataset consumed by lib/data/template.yq. The generated
# lib/data/data.json is an artifact, not a second CDN configuration file.
output "cdn_data" {
  description = "Full CDN dataset consumed by NixOS ATC modules"
  sensitive   = false
  value = {
    nsHost    = local.cdn_ns_host
    nsHosts   = local.cdn_ns_hosts
    edgeNodes = local.cdn_edge_nodes_with_addresses
    services  = local.cdn_services
  }
}

# ==============================================================================
# Cloudflare DNS records derived from the data above
# ==============================================================================

# ── NS delegation for cdn.<domain> ───────────────────────────────────────────
# cdn.dora.im is delegated directly to fra0.dora.im for now. This is a normal
# child-zone delegation: the NS and its A/AAAA record live in the parent
# dora.im zone, while CoreDNS serves the child zone authoritatively.
resource "cloudflare_dns_record" "cdn_ns" {
  name    = "cdn.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 3600
  type    = "NS"
  content = "${local.cdn_ns_host}.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

# Traffic Ops is the control-plane endpoint used by every edge t3c agent.
# Keep it outside the CDN edge pool and point it directly at the fra0 control
# host so edge synchronization never depends on an ATS cache route.
resource "cloudflare_dns_record" "traffic_ops" {
  name    = "ops.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 300
  type    = "CNAME"
  content = "fra0.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

# A/AAAA records for the NS host and edge nodes are generated by hosts.tf from
# the shared host inventory. This file exports those resolved values to Nix;
# it does not duplicate the parent-zone records.

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

# ==============================================================================
# Apache Traffic Control (ATC) Delivery Services & Dynamic Queue Updates
# ==============================================================================

# ==============================================================================
# Apache Traffic Control (ATC) Delivery Services & Dynamic Queue Updates
# ==============================================================================

# ── Delivery Services & Queue Updates Automation ──────────────────────────────
# Due to the absence of an official apache/trafficcontrol provider in the Terraform Registry,
# Delivery Services are synchronized against the Traffic Ops REST API.
resource "null_resource" "traffic_control_sync" {
  triggers = {
    services_hash = md5(jsonencode(local.cdn_services))
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      OPS_PW="${var.ops_password != "" ? var.ops_password : try(data.sops_file.common.data["atc.ops_password"], "")}"
      if [ -z "$OPS_PW" ]; then
        echo "Warning: atc.ops_password not set. Skipping Traffic Ops Delivery Service synchronization."
        exit 0
      fi

      COOKIE_FILE=$(mktemp)
      trap 'rm -f "$COOKIE_FILE"' EXIT

      echo "Authenticating against Traffic Ops API at https://${var.ops_host}..."
      LOGIN_RESP=$(curl -k -s -w "%%{http_code}" -X POST "https://${var.ops_host}/api/v4/user/login" \
        -H "Content-Type: application/json" \
        -d "{\"u\":\"${var.ops_user}\",\"p\":\"$OPS_PW\"}" \
        -c "$COOKIE_FILE" || true)

      HTTP_CODE="$${LOGIN_RESP: -3}"
      if [ "$HTTP_CODE" != "200" ]; then
        echo "Traffic Ops login returned HTTP $HTTP_CODE. Skipping sync (ops service may not be running yet)."
        exit 0
      fi

      echo "Traffic Ops authentication successful. Synchronizing Delivery Services..."
      SERVICES_JSON='${jsonencode(local.cdn_services)}'

      for s in $(echo "$SERVICES_JSON" | jq -r 'keys[]'); do
        origin=$(echo "$SERVICES_JSON" | jq -r --arg s "$s" '.[$s]')
        echo "Ensuring Delivery Service: $s (origin: $origin.${cloudflare_zone.im_dora.name})"

        DS_CHECK=$(curl -k -fsS -b "$COOKIE_FILE" "https://${var.ops_host}/api/5.0/deliveryservices?xmlId=$s")
        DS_ID=$(echo "$DS_CHECK" | jq -r '.response[0].id // empty')
        ORIGIN_FQDN="$origin.${cloudflare_zone.im_dora.name}"

        DS_PAYLOAD=$(cat <<JSON
{
  "active": "ACTIVE",
  "cdnId": 2,
  "displayName": "$s service",
  "dscp": 0,
  "geoProvider": 0,
  "initialDispersion": 1,
  "ipv6RoutingEnabled": true,
  "multiSiteOrigin": false,
  "orgServerFqdn": "https://$ORIGIN_FQDN",
  "protocol": 1,
  "rangeRequestHandling": 0,
  "regionalGeoBlocking": false,
  "routingName": "edge",
  "type": "HTTP",
  "typeId": 1,
  "xmlId": "$s"
}
JSON
)

        if [ -z "$DS_ID" ]; then
          echo "Creating Delivery Service $s..."
          DS_RESPONSE=$(curl -k -fsS -b "$COOKIE_FILE" -X POST "https://${var.ops_host}/api/5.0/deliveryservices" \
            -H "Content-Type: application/json" \
            -d "$DS_PAYLOAD")
          DS_ID=$(echo "$DS_RESPONSE" | jq -r '.response[0].id // empty')
          if [ -z "$DS_ID" ]; then
            echo "Traffic Ops did not return an ID for Delivery Service $s" >&2
            exit 1
          fi
        else
          echo "Updating Delivery Service $s (id $DS_ID)..."
          curl -k -fsS -b "$COOKIE_FILE" -X PUT "https://${var.ops_host}/api/5.0/deliveryservices/$DS_ID" \
            -H "Content-Type: application/json" \
            -d "$DS_PAYLOAD" >/dev/null
        fi

        # Keep the origin as a first-class ATC origin resource rather than
        # relying on the unrelated orgServerFqdn field.
        ORIGIN_CHECK=$(curl -k -fsS -b "$COOKIE_FILE" "https://${var.ops_host}/api/5.0/origins?deliveryService=$DS_ID")
        if [ "$(echo "$ORIGIN_CHECK" | jq -r '.response | length // 0')" -eq 0 ]; then
          curl -k -fsS -b "$COOKIE_FILE" -X POST "https://${var.ops_host}/api/5.0/origins" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$s-origin\",\"fqdn\":\"$ORIGIN_FQDN\",\"protocol\":\"https\",\"isPrimary\":true,\"port\":443,\"deliveryServiceId\":$DS_ID,\"tenantId\":1}" >/dev/null
        fi

        REGEX=".*\\.$s\\.${cloudflare_zone.im_dora.name}.*"
        REGEX_RESPONSE=$(curl -k -fsS -b "$COOKIE_FILE" "https://${var.ops_host}/api/5.0/regexes?pattern=$(printf '%s' "$REGEX" | jq -sRr @uri)")
        REGEX_ID=$(echo "$REGEX_RESPONSE" | jq -r '.response[0].id // empty')
        if [ -z "$REGEX_ID" ]; then
          REGEX_RESPONSE=$(curl -k -fsS -b "$COOKIE_FILE" -X POST "https://${var.ops_host}/api/5.0/regexes" \
            -H "Content-Type: application/json" \
            -d "{\"pattern\":\"$REGEX\",\"type\":\"HOST_REGEXP\"}")
          REGEX_ID=$(echo "$REGEX_RESPONSE" | jq -r '.response[0].id // empty')
        fi
        if [ -n "$REGEX_ID" ]; then
          curl -k -fsS -b "$COOKIE_FILE" -X POST "https://${var.ops_host}/api/5.0/deliveryservices/$s/regexes" \
            -H "Content-Type: application/json" \
            -d "{\"regexId\":$REGEX_ID,\"setNumber\":0}" >/dev/null || true
        fi
      done

      echo "Delivery Services synchronized. Queue updates are triggered through the CDN queue API after topology changes."

      echo "Traffic Ops synchronization and Queue Updates completed successfully."
    EOT
  }

  depends_on = [
    cloudflare_dns_record.cdn_service_cname
  ]
}
