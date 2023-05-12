{ config
, self
, inputs
, lib
, getSystem
, ...
}:
let
  inherit (inputs.nixpkgs.lib) nixosSystem;

  nixosModules = self.lib.rake ../nixos/modules;
  hmModules = self.lib.rake ../home-manager/modules;

  commonNixosModules =
    nixosModules.base.all
    ++ [
      inputs.home-manager.nixosModules.home-manager
      inputs.sops-nix.nixosModules.sops
      inputs.impermanence.nixosModules.impermanence
      inputs.disko.nixosModules.disko
      {
        lib.self = self.lib;
        home-manager = {
          sharedModules = commonHmModules;
          extraSpecialArgs = hmSpecialArgs;
        };
        system.configurationRevision =
          if self ? rev
          then self.rev
          else null;
      }
    ];

  commonHmModules =
    hmModules.base.all
    ++ [
      inputs.sops-nix.homeManagerModules
      inputs.impermanence.nixosModules.home-manager.impermanence
      {
        lib.self = self.lib;
      }
    ];

  nixosSpecialArgs = {
    inherit inputs self nixosModules;
  };

  hmSpecialArgs = {
    inherit inputs self hmModules;
  };

  mkHost =
    { name
    , configurationName ? name
    , system
    , extraModules ? [ ]
    ,
    }: {
      ${name} = nixosSystem {
        inherit system;
        inherit ((getSystem system).allModuleArgs) pkgs;
        specialArgs = nixosSpecialArgs;
        modules =
          commonNixosModules
          ++ extraModules
          ++ lib.optional (configurationName != null) ../nixos/hosts/${configurationName}
          ++ [
            ({ lib, ... }: {
              networking.hostName = lib.mkDefault name;
            })
          ];
      };
    };
in
{
  passthru = {
    inherit nixosModules hmModules;
  };

  flake.nixosConfigurations = lib.mkMerge [
    (mkHost {
      name = "fra0";
      system = "x86_64-linux";
    })
  ];
}
