{
  nixosModules,
  config,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      ../../modules/base/modules/easytier-member.nix
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
  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    realBandwidth = 200;
    rtt = 110; # ms，国际线路
    ram = 4096; # MB，可用内存
    cpus = 4; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };

  services.easytierMesh.member = {
    enable = true;
    bootstrapHost = "et.${config.networking.domain}";
    ipv4 = "10.144.0.4/24";
    lowResource = true;
    latencyFirst = true;
    privateMode = true;
    disableIPv6 = true;
  };
}
