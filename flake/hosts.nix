{
  self,
  inputs,
  lib,
  getSystem,
  ...
}:
let
  inherit (inputs.nixpkgs.lib) nixosSystem;

  nixosModules = self.lib.rake ../nixos/modules;
  hmModules = self.lib.rake ../home-manager/modules;

  commonNixosModules = nixosModules.base.all ++ [
    inputs.home-manager.nixosModules.home-manager
    inputs.nur.modules.nixos.default
    {
      lib.self = self.lib;
      home-manager = {
        sharedModules = commonHmModules;
        extraSpecialArgs = hmSpecialArgs;
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
      };
      system.configurationRevision = self.rev or null;
    }
  ];

  commonHmModules = hmModules.base.all ++ [
    inputs.nur.modules.homeManager.default
    {
      lib.self = self.lib;
    }
  ];

  nixosSpecialArgs = {
    inherit
      inputs
      self
      nixosModules
      getSystem
      ;
  };

  hmSpecialArgs = {
    inherit inputs self hmModules;
  };

  mkHost =
    {
      name,
      configurationName ? name,
      system,
      extraModules ? [ ],
    }:
    {
      ${name} = nixosSystem {
        inherit system;
        specialArgs = nixosSpecialArgs;
        modules =
          commonNixosModules
          ++ extraModules
          ++ lib.optional (configurationName != null) ../nixos/hosts/${configurationName}
          ++ [
            (
              { lib, ... }:
              {
                networking.hostName = lib.mkDefault name;
                # _module.args.pkgs = lib.mkForce (getSystem system).allModuleArgs.pkgs;
                nixpkgs.system = system;
              }
            )
          ];
        extraModules = [ inputs.colmena.nixosModules.deploymentOptions ];
      };
    };
in
{
  passthru = {
    inherit nixosModules hmModules;
  };

  flake.nixosConfigurations = lib.mkMerge [
    (mkHost {
      name = "surface";
      system = "x86_64-linux";
      extraModules = with inputs.nixos-hardware.nixosModules; [
        microsoft-surface-common
      ];
    })
    (mkHost {
      name = "arx8";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "ams0";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "dfw0";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "hkg4";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "fra1";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "vie0";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "nue0";
      system = "x86_64-linux";
    })
    # (mkHost {
    #   name = "isk";
    #   system = "x86_64-linux";
    # })
  ];
}
