{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.small
      nixosModules.services.traefik
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        needProxy = true;
        proxyHost = "nue0.dora.im";
      })
      # nixosModules.services.tuic
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];
}
