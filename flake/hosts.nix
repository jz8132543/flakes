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
  overlays = import ../lib/overlays.nix { inherit inputs lib self; };

  commonModulePrelude = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nur.modules.nixos.default
    {
      nixpkgs.overlays = overlays;
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

  lixModules =
    lib.optionals (inputs.lix ? nixosModule) [ inputs.lix.nixosModule ]
    ++ lib.optionals (inputs.lix ? nixosModules) [ inputs.lix.nixosModules.default ];

  commonNixosModules =
    nixosModules.base.all
    ++ commonModulePrelude
    ++ lixModules
    ++ [
      inputs.colmena.nixosModules.deploymentOptions
    ];

  commonColmenaModules = nixosModules.base.all ++ commonModulePrelude ++ lixModules;

  commonHmModules =
    hmModules.base.all
    ++ hmModules.services.all
    ++ [
      inputs.plasma-manager.homeModules.plasma-manager
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

  hostDefinitions = {
    surface = {
      system = "x86_64-linux";
      extraModules = with inputs.nixos-hardware.nixosModules; [
        microsoft-surface-common
      ];
    };
    arx8 = {
      system = "x86_64-linux";
    };
    hkg4 = {
      system = "x86_64-linux";
    };
    nue0 = {
      system = "x86_64-linux";
    };
    isk = {
      system = "x86_64-linux";
    };
    tyo0 = {
      system = "x86_64-linux";
    };
    hkg5 = {
      system = "x86_64-linux";
    };
    cu = {
      system = "x86_64-linux";
    };
    sjc0 = {
      system = "x86_64-linux";
    };
    tyo1 = {
      system = "x86_64-linux";
    };
    can0 = {
      system = "x86_64-linux";
    };
    can1 = {
      system = "x86_64-linux";
    };
    can2 = {
      system = "x86_64-linux";
    };
    xiy0 = {
      system = "x86_64-linux";
    };
    xiy1 = {
      system = "x86_64-linux";
    };
    xiy2 = {
      system = "x86_64-linux";
    };
  };

  mkHostModules =
    {
      name,
      configurationName ? name,
      system,
      extraModules ? [ ],
    }:
    extraModules
    ++ lib.optional (configurationName != null) ../nixos/hosts/${configurationName}
    ++ [
      (
        { lib, ... }:
        {
          networking.hostName = lib.mkDefault name;
          # _module.args.pkgs = lib.mkForce (getSystem system).allModuleArgs.pkgs;
          nixpkgs.hostPlatform = system;
          nix.package = lib.mkDefault inputs.lix.packages.${system}.default;
        }
      )
    ];

  mkHost =
    name: host:
    nixosSystem {
      specialArgs = nixosSpecialArgs;
      modules = commonNixosModules ++ mkHostModules (host // { inherit name; });
    };

  mkColmenaHost = name: host: commonColmenaModules ++ mkHostModules (host // { inherit name; });

  colmenaModules = lib.mapAttrs mkColmenaHost hostDefinitions;

  nixosConfigurations = lib.mapAttrs mkHost hostDefinitions;

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
            inherit overlays;
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
                nix.package = pkgs.lix;
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
  options.flake.hostNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  options.flake.colmenaModules = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.unspecified);
    default = { };
  };

  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
  config = {
    flake.hostNames = lib.attrNames hostDefinitions;
    flake.colmenaModules = colmenaModules;
    passthru = {
      inherit nixosModules hmModules;
    };
    flake.nixosConfigurations = nixosConfigurations;

    flake.homeConfigurations = lib.mkMerge [
      (mkHome {
        name = "localhost";
        user = "tippy";
        system = "x86_64-linux";
        configurationName = null;
      })
      (mkHome {
        name = "shg0";
        user = "tippy";
        system = "x86_64-linux";
      })
    ];
  };
}
