{ self
, nixosModules
, ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.mail.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.headscale
      nixosModules.services.postgres
      nixosModules.services.vaultwarden
      nixosModules.services.matrix
      nixosModules.services.authentik
      # nixosModules.services.derp
    ];
}
