{
  nixosModules,
  config,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.postgres
      (import nixosModules.services.matrix {PG = "127.0.0.1";})
    ];
  environment.isCN = true;
}
