{
  self,
  inputs,
  lib,
  getSystem,
  ...
}:
let
  inherit (inputs.nixpkgs.lib) nixosSystem;

  # Fix infinite recursion by importing lib locally instead of via self
  selfLib = import ../lib { inherit inputs lib; };
  nixosModules = selfLib.rake ../nixos/modules;
  hmModules = selfLib.rake ../home-manager/modules;

  commonNixosModules = nixosModules.base.all ++ [
    inputs.home-manager.nixosModules.home-manager
    inputs.nur.modules.nixos.default
    {
      nixpkgs.overlays = [ (import ../pkgs).overlay ];
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
    {
      lib.self = selfLib;
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
    inputs = builtins.removeAttrs inputs [ "self" ];
    inherit hmModules;
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
                nixpkgs.hostPlatform = system;
              }
            )
          ];
        extraModules = [ inputs.colmena.nixosModules.deploymentOptions ];
      };
    };

  mkHome =
    {
      name,
      user,
      system,
      extraModules ? [ ],
    }:
    {
      "${user}@${name}" = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        modules =
          commonHmModules
          ++ hmModules.${user}.all
          ++ extraModules
          ++ [
            {
              home = {
                username = user;
                homeDirectory = "/home/${user}";
              };
              targets.genericLinux.enable = true;
            }
          ];
        extraSpecialArgs = hmSpecialArgs // {
          osConfig = {
            networking.domain = "dora.im"; # Fallback/Default domain
            networking.fw-proxy.enable = false;
            environment.domains = [ ];
            ports.ssh = 22;
            sops-file.get = name: "${self}/secrets/${name}";
            services.xserver.enable = false; # Assuming headless for remote deploy
          };
        };
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

  flake.homeConfigurations = lib.mkMerge [
    # (mkHome {
    #   name = "nue0";
    #   user = "tippy";
    #   system = "x86_64-linux";
    # })
    # Generic localhost configuration for remote home-manager deployment
    (mkHome {
      name = "localhost";
      user = "tippy";
      system = "x86_64-linux";
    })
  ];
}
