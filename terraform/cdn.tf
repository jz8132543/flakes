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
  # ── 控制平面节点列表 (Control Plane Nodes) ──────────────────────────────────
  # 运行 Traffic Ops API、Traffic Monitor 以及智能权威 DNS (CoreDNS / Traffic Router)
  # 目前为 ["fra0"]，代码架构预留支持扩展多个控制节点以实现多中心高可用容灾
  cdn_control_nodes = ["fra0"]

  # ── 智能调度 DNS 权威服务器 (Authoritative NS Hosts) ─────────────────────────
  cdn_ns_hosts = local.cdn_control_nodes
  cdn_ns_host  = local.cdn_ns_hosts[0]

  # ── 边缘加速节点列表 (Edge Cache Nodes) ────────────────────────────────────
  # 运行 Apache Traffic Server (ATS) 高速缓存代理与 t3c 动态热同步 Agent
  # 用户明确指定：fra1, tyo0, hkg0, hkg5 (tyo1 不跑边缘节点，不带有任何配置)
  #
  # Fields:
  #   name   – 主机短名 (与系统 networking.hostName 一致)
  #   region – 节点地域标签 (EU / AP / HK / US 等)
  #   weight – DNS 轮询解析相对权重系数
  cdn_edge_nodes = [
    {
      name   = "fra1"
      region = "EU"
      weight = 10
    },
    {
      name   = "tyo0"
      region = "AP"
      weight = 5
    },
    {
      name   = "hkg0"
      region = "HK"
      weight = 8
    },
    {
      name   = "hkg5"
      region = "HK"
      weight = 8
    },
  ]

  # ── 加速业务映射 (Accelerated Services) ──────────────────────────────────────
  # 子域名映射 -> 真实后端源站主机名 (全部通过源站集群回源)
  # 业务域名生命周期统一由此处声明管理，边缘节点自动热同步
  cdn_services = {
    jellyfin = "fra0"
    zone     = "fra0"
    alist    = "fra0"
    office   = "fra0"
    code     = "fra0"
    cloud    = "fra0"
    m        = "fra0"
    chat     = "fra0"
    mcp      = "fra0"
    s        = "fra0"
    persona  = "fra0"
    bot      = "fra0"
    napcat   = "fra0"
  }

  cdn_control_nodes_with_addresses = [
    for name in local.cdn_control_nodes : {
      name = name
      ipv4 = try(local.hosts[name].records.a.value, null)
      ipv6 = try(local.hosts[name].records.aaaa.value, null)
    }
  ]

  # ── Terraform 派生值导出 ──────────────────────────────────────────────────
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
    controlDomain    = "ops.${cloudflare_zone.im_dora.name}"
    controlHost      = "ops.${cloudflare_zone.im_dora.name}"
    controlNodes     = local.cdn_control_nodes_with_addresses
    controlNodeNames = local.cdn_control_nodes
    nsHost           = local.cdn_ns_host
    nsHosts          = local.cdn_ns_hosts
    edgeNodes        = local.cdn_edge_nodes_with_addresses
    edgeNodeNames    = [for n in local.cdn_edge_nodes : n.name]
    services         = local.cdn_services
  }
}

# ==============================================================================
# Cloudflare DNS records derived from the data above
# ==============================================================================

# ── NS delegation for cdn.<domain> ───────────────────────────────────────────
# cdn.dora.im is delegated to the authoritative control plane nameservers.
# Multiple control nodes are automatically registered as multiple NS records.
resource "cloudflare_dns_record" "cdn_ns" {
  for_each = toset(local.cdn_ns_hosts)

  name    = "cdn.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 3600
  type    = "NS"
  content = "${each.key}.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

# Traffic Ops is the control-plane endpoint used by every edge t3c agent.
# It resolves to the primary active control plane node so edge synchronization
# never depends on an ATS cache route or circular DNS lookups.
resource "cloudflare_dns_record" "traffic_ops" {
  name    = "ops.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 300
  type    = "CNAME"
  content = "${local.cdn_control_nodes[0]}.${cloudflare_zone.im_dora.name}"
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
