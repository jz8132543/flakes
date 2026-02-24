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

  commonHmModules =
    hmModules.base.all
    ++ hmModules.services.all
    ++ [
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
    inputs = removeAttrs inputs [ "self" ];
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
      configurationName ? name,
      extraModules ? [ ],
    }:
    {
      "${user}@${name}" =
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = import ../lib/overlays.nix { inherit inputs lib self; };
          };
        in
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules =
            commonHmModules
            ++ hmModules.${user}.all
            ++ extraModules
            ++ lib.optional (configurationName != null) ../home-manager/hosts/${configurationName}.nix
            ++ [
              {
                home = {
                  username = user;
                  homeDirectory = "/home/${user}";
                  activation.enableLinger = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                    ${pkgs.systemd}/bin/loginctl enable-linger $(whoami)
                  '';
                };
                nix.package = pkgs.nix;
                targets.genericLinux.enable = true;

                # Mock osConfig for standalone Home Manager
                _module.args.osConfig = rec {
                  networking.hostName = name;
                  networking.domain = "dora.im";
                  networking.fqdn = "${networking.hostName}.${networking.domain}";
                  environment.domains = [ ];
                  sops-file.get = name: "${self}/secrets/${name}";

                  inherit
                    ((import ../nixos/modules/base/module/misc/ports.nix {
                      inherit lib;
                      config = { };
                    }).config
                    )
                    ports
                    ;

                  inherit pkgs;
                };
              }
            ];
          extraSpecialArgs = hmSpecialArgs;
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
      name = "hkg4";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "nue0";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "isk";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "tyo0";
      system = "x86_64-linux";
    })
    (mkHost {
      name = "hkg5";
      system = "x86_64-linux";
    })
  ];

  flake.homeConfigurations =
    (mkHome {
      name = "localhost";
      user = "tippy";
      system = "x86_64-linux";
      configurationName = null;
    })
    // (mkHome {
      name = "shg0";
      user = "tippy";
      system = "x86_64-linux";
    })
    // (mkHome {
      name = "tyo0";
      user = "tippy";
      system = "x86_64-linux";
    })
    // (mkHome {
      name = "tyo0";
      user = "tippy";
      system = "x86_64-linux";
    })
    // (mkHome {
      name = "cu";
      user = "tippy";
      system = "x86_64-linux";
    });
}
