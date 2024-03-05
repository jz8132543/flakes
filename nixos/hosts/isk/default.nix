{
  nixosModules,
  lib,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      ./_steam
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.services.postgres
      nixosModules.services.derp
      (import nixosModules.services.matrix {PG = "127.0.0.1";})
    ];
  services.qemuGuest.enable = true;

  environment.isNAT = true;
  environment.isCN = true;

  ports.derp-stun = lib.mkForce 3440;
  # services.traefik.staticConfigOptions.entryPoints.https.address = lib.mkForce ":8443";
}
