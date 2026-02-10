{ nixosModules, ... }:
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
      nixosModules.services.media.nixflix
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];
}
