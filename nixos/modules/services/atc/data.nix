# ============================================================
# ATC CDN Data — THE ONLY FILE THAT NEEDS HUMAN EDITING
# ============================================================
# Two tables:
#   edgeNodes  — CDN edge nodes that serve traffic to clients.
#   services   — service-label → upstream-origin-hostname mapping.
#
# Rules:
#   • This file MUST NOT import anything or contain logic.
#   • To add a new CDN-accelerated service:
#       1. Add one line in `services` below.
#       2. Add one CNAME in terraform/cloudflare.tf pointing
#          <label>.dora.im → <label>.cdn.dora.im  (proxy = false).
#   • No other files need to change.
# ============================================================
{
  # ── Edge nodes ───────────────────────────────────────────
  # Fields:
  #   name    – short hostname (must match networking.hostName on that machine)
  #   ipv4    – public IPv4 (required)
  #   ipv6    – public IPv6 (optional, null if absent)
  #   region  – geographic tag used for future geo-steering (AP / HK / EU / US)
  #   weight  – relative weight for future weighted-round-robin (default 1)
  edgeNodes = [
    {
      name = "tyo0";
      ipv4 = "45.66.130.158";
      ipv6 = null;
      region = "AP";
      weight = 1;
    }
    {
      name = "tyo1";
      ipv4 = "216.23.85.218";
      ipv6 = null;
      region = "AP";
      weight = 1;
    }
    {
      name = "hkg5";
      ipv4 = "216.23.94.148";
      ipv6 = null;
      region = "HK";
      weight = 1;
    }
    {
      name = "sjc0";
      ipv4 = "45.143.130.230";
      ipv6 = null;
      region = "US";
      weight = 1;
    }
    {
      name = "nue0";
      ipv4 = "185.216.178.70";
      ipv6 = "2a03:4000:4f:92d::";
      region = "EU";
      weight = 1;
    }
    {
      name = "fra0";
      ipv4 = "23.165.200.135";
      ipv6 = null;
      region = "EU";
      weight = 1;
    }
  ];

  # ── Services ─────────────────────────────────────────────
  # Maps a short service label to the upstream origin hostname
  # (without domain suffix — the module appends config.networking.domain).
  #
  # Examples:
  #   jellyfin = "nue0"  →  jellyfin.cdn.<domain> resolves to all edge IPs;
  #                          edges proxy SNI `jellyfin.<domain>` → nue0.<domain>:443
  #   zone     = "fra0"  →  same pattern, upstream is fra0
  #
  # Add one line here + one CNAME in cloudflare.tf to accelerate a new service.
  services = {
    jellyfin = "nue0";
    zone = "fra0";
    alist = "fra0";
    office = "fra0";
    code = "fra0";
    cloud = "fra0";
    api = "fra0";
    cpa = "fra0";
    m = "fra0";
    chat = "fra0";
    cache = "fra0";
    s = "fra0";
  };
}
