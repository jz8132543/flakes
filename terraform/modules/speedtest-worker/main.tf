terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.16.0"
    }
  }
}

variable "account_id" {
  type      = string
  sensitive = true
}

variable "zone_id" {
  type = string
}

variable "hostname" {
  type = string
}

resource "cloudflare_workers_script" "this" {
  account_id         = var.account_id
  script_name        = "speedtest-dora-im"
  main_module        = "worker.mjs"
  content_file       = "${path.module}/worker.mjs"
  content_sha256     = filesha256("${path.module}/worker.mjs")
  compatibility_date = "2026-11-17"
  usage_model        = "standard"

  observability = {
    enabled = false
  }
}

# Custom Domains provision their own DNS record and edge certificate.
resource "cloudflare_workers_custom_domain" "this" {
  account_id  = var.account_id
  environment = "production"
  hostname    = var.hostname
  service     = cloudflare_workers_script.this.script_name
  zone_id     = var.zone_id
}

output "url" {
  value = "https://${var.hostname}"
}
