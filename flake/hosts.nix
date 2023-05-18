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
      inputs.nur.nixosModules.nur
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
      inputs.nur.hmModules.nur
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
    (mkHost {
      name = "surface";
      system = "x86_64-linux";
      extraModules = with inputs.nixos-hardware.nixosModules;[
        microsoft-surface-common
      ];
    })
  ];
}
