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
      nixosModules.optimize.infini
      nixosModules.optimize.anti-balloon
      nixosModules.optimize.brutal
      nixosModules.services.networking.dn42.mesh
      # nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.services.atc.edge
      # nixosModules.services.derp
      (import nixosModules.services.xray { })
    ];

  environment.networkTune = {
    enable = true;
    bandwidth = 500; # Mbps 单向
    realBandwidth = 500;
    rtt = 200; # ms
    ram = 425; # MB，预留内存给Xray
    cpus = 1; # vCPU 数
    highLoss = true;
    # 禁用 FQ 速率整形墙，配合 BBRv1 的野蛮发包，不受任何人工带宽限制
    fqMaxrate = 0;
  };
}
