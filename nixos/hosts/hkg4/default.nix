{
  nixosModules,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        needProxy = true;
      })
      # nixosModules.services.tuic
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];

  environment.networkOmnitt = {
    realbandwith = 200; # local bandwidth (Mbps)
    latencyMs = 110; # ms，国际线路
    memoryMB = 4096; # MB，可用内存
  };
}
