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
      nixosModules.services.traefik
      (import nixosModules.services.xray { })
    ];

  environment.networkTune = {
    enable = true;
    ram = 1945;
    cpus = 2;
  };

  services.openssh.ports = [
    22222
    22
  ];
}
