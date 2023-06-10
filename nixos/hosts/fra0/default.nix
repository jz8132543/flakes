{
  self,
  nixosModules,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.mail.all
    ++ nixosModules.services.ssh-honeypot.all
    ++ nixosModules.services.hydra.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.headscale
      nixosModules.services.derp
      nixosModules.services.postgres
      nixosModules.services.vaultwarden
      nixosModules.services.matrix
      nixosModules.services.keycloak
    ];
}
