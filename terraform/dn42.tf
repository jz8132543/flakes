# ==============================================================================
# DN42 Data — THE ONLY FILE THAT NEEDS HUMAN EDITING FOR DN42 CHANGES
# ==============================================================================
# This file is the single source of truth for the DN42 BGP / Mesh infrastructure.
# Both Terraform (outputs) and NixOS (Bird, WireGuard, Babel) consume this data.
#
# After editing this file, run terraform-pipe. Its output extraction writes
# lib/data/data.json, which is consumed directly by the DN42 NixOS modules.
#
# To add a new external peer:
#   Add an entry under `dn42_external_peers` below.
# To add a new node to the mesh:
#   Add an entry under `dn42_mesh_nodes` below with role "border" or "internal".
# ==============================================================================

variable "dn42_asn" {
  default = 4242420115
  type    = number
}

variable "dn42_v4_cidr" {
  default = "172.20.232.0/26"
  type    = string
}

variable "dn42_v6_cidr" {
  default = "fd53:90fd:4bb6::/48"
  type    = string
}

locals {
  dn42_mesh_listen_port = 51821

  # ── 1. Dynamic Public Peering Endpoint Targets (peer1, peer2, ... .dora.im) ──
  # Define the list/set of border hosts for public peering.
  # Terraform automatically computes `peer1 -> targets[0]`, `peer2 -> targets[1]`...
  # and provisions Cloudflare CNAME records:
  #   peer1.dora.im -> fra0.dora.im  (Pubkey: aPD/ej1dswyojJ+u41Pgsw1XSca7tMOwdhEpiv4Ntl0=)
  #   peer2.dora.im -> hkg0.dora.im  (Pubkey: k4Um5FjJ1yS7aDDvs9v9jSpUePFL7YcATFr5q79y3yU=)
  #   peer3.dora.im -> cu.dora.im    (Pubkey: PJ24FpCqARflKn0Cbhg/c9dG8TuViBcFrco5b2BLdw8=)
  #
  # When registering at external peering websites, fill in:
  #   Endpoint:   peerX.dora.im:51820
  #   Public Key: The static public key corresponding to peerX above
  #
  # When swapping a server, simply swap the hostname in `dn42_peer_targets` below.
  # External peers need 0 updates to either domain or public key!
  dn42_peer_targets = {
    peer1 = "fra0"
    peer2 = "hkg0"
    peer3 = "cu"
  }

  dn42_peer_aliases = local.dn42_peer_targets

  dn42_peer_public_keys = {
    peer1 = "aPD/ej1dswyojJ+u41Pgsw1XSca7tMOwdhEpiv4Ntl0="
    peer2 = "k4Um5FjJ1yS7aDDvs9v9jSpUePFL7YcATFr5q79y3yU="
    peer3 = "PJ24FpCqARflKn0Cbhg/c9dG8TuViBcFrco5b2BLdw8="
  }

  # ── 2. Mesh Nodes (All hosts participating in DN42) ──────────────────────────
  # Roles:
  #   - "border": fra0, hkg0, cu (runs eBGP + iBGP + Babel)
  #   - "internal": tyo0, tyo1, hkg5, sjc0, arx8, surface (runs Babel; iBGP optional)
  dn42_mesh_nodes = {
    # ── Borders ──
    fra0 = {
      role       = "border"
      ibgp       = true
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "fra0.dora.im:${local.dn42_mesh_listen_port}"
    }
    hkg0 = {
      role       = "border"
      ibgp       = true
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "hkg0.dora.im:${local.dn42_mesh_listen_port}"
    }
    cu = {
      role       = "border"
      ibgp       = true
      listenPort = local.dn42_mesh_listen_port
      endpoint = {
        cuv6 = "cuv6.dora.im"
        cmv6 = "cmv6.dora.im"
        cu   = "cu.dora.im"
        cm   = "cm.dora.im"
    } }

    # ── Internals ──
    tyo0 = {
      role       = "internal"
      ibgp       = false # Set true if you want this node to participate in iBGP
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "tyo0.dora.im:${local.dn42_mesh_listen_port}"
    }
    tyo1 = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "tyo1.dora.im:${local.dn42_mesh_listen_port}"
    }
    hkg5 = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "hkg5.dora.im:${local.dn42_mesh_listen_port}"
    }
    sjc0 = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "sjc0.dora.im:${local.dn42_mesh_listen_port}"
    }
    fra1 = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = "fra1.dora.im:${local.dn42_mesh_listen_port}"
    }
    arx8 = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = null
    }
    surface = {
      role       = "internal"
      ibgp       = false
      listenPort = local.dn42_mesh_listen_port
      endpoint   = null
    }
  }

  # ── 3. External eBGP Peers ───────────────────────────────────────────────────
  # Define external peers here. Each peer is attached to a specific border host.
  dn42_external_peers = {
    g-load-de2 = {
      host            = "fra0"
      asn             = 4242423914
      endpoint        = "de2.g-load.eu:20137"
      listenPort      = 51820
      publicKey       = "B1xSG/XTJRLd+GrWDsB06BqnIq8Xud93YVh/LYYYtUY="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
    g-load-hk1 = {
      host            = "hkg0"
      asn             = 4242423914
      endpoint        = "hk1.g-load.eu:20087"
      listenPort      = 51820
      publicKey       = "sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
    g-load-uk1 = {
      host            = "cu"
      asn             = 4242423914
      endpoint        = "uk1.g-load.eu:20031"
      listenPort      = 51820
      publicKey       = "sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8="
      linkLocal       = "fe80::ade0"
      ourLinkLocal    = "fe80::ade1"
      latency         = "10ms"
      bandwidth       = "1000m"
      crypto          = "wireguard"
      extendedNextHop = true
    }
  }
}

# ── Cloudflare CNAME Records for Peering Endpoints ───────────────────────────
# Automatically creates peer1.dora.im, peer2.dora.im, peer3.dora.im ...
resource "cloudflare_dns_record" "dn42_peer_cnames" {
  for_each = local.dn42_peer_aliases

  name    = "${each.key}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1 # automatic
  type    = "CNAME"
  content = "${each.value}.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}

output "dn42_v4_cidr" {
  value     = var.dn42_v4_cidr
  sensitive = false
}

output "dn42_v6_cidr" {
  value     = var.dn42_v6_cidr
  sensitive = false
}

# Output the full dataset consumed by lib/data/template.yq. The generated
# lib/data/data.json is an artifact, not a configuration file.
output "dn42_data" {
  description = "Full DN42 dataset consumed by NixOS DN42 modules"
  sensitive   = false
  value = {
    asn            = var.dn42_asn
    ipv4           = var.dn42_v4_cidr
    ipv6           = var.dn42_v6_cidr
    mesh           = local.dn42_mesh_nodes
    externalPeers  = local.dn42_external_peers
    peerAliases    = local.dn42_peer_aliases
    peerPublicKeys = local.dn42_peer_public_keys
  }
}

