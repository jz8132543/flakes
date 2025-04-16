{ nixosModules, lib, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.doraim
      nixosModules.services.derp
      # nixosModules.services.stun
      nixosModules.services.proxy
      # nixosModules.services.tuic
      nixosModules.services.searx
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      nixosModules.services.murmur
      nixosModules.services.teamspeak
      # nixosModules.services.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];
  nix.gc.options = lib.mkForce "-d";
}
