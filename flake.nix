{
  description = "nixos-config";

  inputs = {
    sops-nix.url = github:Mic92/sops-nix;
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-cn = {
      url = "github:nixos-cn/flakes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager , sops-nix, nixos-cn, nur, ... }@inputs: with nixpkgs.lib;
    let
      username = "tippy";
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      overlays = map (f: f.overlay) [  ];
      baseSystem =
        { system ? "x86_64-linux", modules ? [], overlay ? true }@config:
        nixosSystem {
          inherit system;
          specialArgs = rec {
            constants = import ./constants;
            flakes = genAttrs (builtins.attrNames inputs)
                (
                  flake:
                    (
                      if (inputs.${flake} ? packages && inputs.${flake}.packages ? ${system})
                      then inputs.${flake}.packages.${system}
                      else {}
                    )
                    // {
                      path = inputs.${flake};
                      nixosModules = inputs.${flake}.nixosModules or {};
                    }
                );
            nixosModules = foldl recursiveUpdate {} (map (flake: flake.nixosModules or {}) (attrValues flakes));
          };
          modules =
              (optional overlay { nixpkgs.overlays = mkBefore overlays; })
              ++ [
                {
                  _module.args.system = system;
                }
              ]
              ++ config.modules;
        };
    in {
      nixosConfigurations = {
        tyo0 = baseSystem rec {
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/tyo0
          ];
        };
        ams0 = baseSystem rec {
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/ams0
          ];
        };
        sin0 = baseSystem rec {
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/sin0
          ];
        };
      };
      # nixosConfigurations = {
      #   tyo0 = nixpkgs.lib.nixosSystem {
      #     system = "x86_64-linux";
      #     modules = [
      #       sops-nix.nixosModules.sops
      #       ./hosts/tyo0
      #     ];
      #   };
      #   ams0 = nixpkgs.lib.nixosSystem {
      #     system = "x86_64-linux";
      #     modules = [
      #       sops-nix.nixosModules.sops
      #       ./hosts/ams0
      #     ];
      #   };
      # };
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home/home.nix ];
      };

    };
}

