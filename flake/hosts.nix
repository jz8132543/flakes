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
            ++ [
              {
                home = {
                  username = user;
                  homeDirectory = "/home/${user}";
                };
                home.packages = [ pkgs.tailscale ];
                targets.genericLinux.enable = true;
              }
            ];
          extraSpecialArgs = hmSpecialArgs // {
            osConfig = rec {
              networking.hostName =
                let
                  hostnameFile = "/nix/config/hostname";
                in
                if builtins.pathExists hostnameFile then
                  lib.strings.trim (builtins.readFile hostnameFile)
                else
                  "localhost";
              networking.domain = "dora.im";
              networking.fqdn = "${networking.hostName}.${networking.domain}";
              networking.fw-proxy.enable = false;
              environment.domains = [ ];
              inherit ((import ../nixos/modules/base/module/misc/ports.nix {
                  inherit lib;
                  config = { };
                }).config) ports;
              nix.settings = {
                substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];
                trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
              };
              sops-file.get = name: "${self}/secrets/${name}";
              services.xserver.enable = false; # Assuming headless for remote deploy
              inherit pkgs;
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
      extraModules = [
        (
          { config, osConfig, ... }:
          {
            sops.age.keyFile = "/nix/config/sops/age/keys.txt";
            services.derp = {
              enable = true;
              hostname = osConfig.networking.fqdn;
              port = 10043;
              stunPort = 3440;
              certMode = "manual";
              certDir = "${config.services.acme.directory}/certificates";
            };
            services.microsocks = {
              enable = true;
              port = osConfig.ports.seedboxProxyPort;
            };
            services.acme = {
              enable = true;
              certs."main" = {
                domain = "*.dora.im";
                aliasNames = [ osConfig.networking.fqdn ];
              };
            };
          }
        )
      ];
    })
  ];
}
