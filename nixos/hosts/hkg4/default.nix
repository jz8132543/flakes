{ nixosModules, lib, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.telegraf
      nixosModules.services.doraim
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        needProxy = true;
        proxyHost = "nue0.dora.im";
      })
      # nixosModules.services.tuic
      nixosModules.services.searx
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      nixosModules.services.murmur
      nixosModules.services.teamspeak
      nixosModules.services.nixflix
      /*
        # ══════════════════════════════════════════════════════════
        # PT Racing & Seeding Configuration (Unsupported in current module)
        # ══════════════════════════════════════════════════════════
        autobrr = true; # Auto-grab FREE torrents from RSS
        # ... (rest of the config commented out)
      */
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];
  nix.gc.options = lib.mkForce "-d";

  # ═══════════════════════════════════════════════════════════════
  # Firewall - Open qBittorrent listening port for PT
  # ═══════════════════════════════════════════════════════════════
  # Port 51413 is essential for incoming peer connections
  # Without it, you can only connect to peers, not receive connections
  # This significantly reduces upload potential!
  networking.firewall = {
    allowedTCPPorts = [
      8081
      51413
    ]; # 51413 = qBittorrent
    allowedUDPPorts = [ 51413 ]; # For uTP protocol
  };
}
