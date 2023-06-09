{
  self,
  nixosModules,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.ssh-honeypot.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.postgres
      nixosModules.services.derp
      nixosModules.services.hydra.hydra-builder-server
    ];
}
