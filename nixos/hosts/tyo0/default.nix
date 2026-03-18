{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.fakehttp
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
      })
    ];

  environment.networkOmnitt = {
    latencyMs = 200; # ms, international link
    memoryMB = 350; # available memory
  };
}
