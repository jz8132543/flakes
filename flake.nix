{
  description = "nixos-config";

  inputs = {
    nixos.url = "github:nixos/nixpkgs/nixos-unstable";
    latest.url = "github:nixos/nixpkgs/master";
    home = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixos";
    };
    nixos-cn = {
      url = "github:nixos-cn/flakes";
      inputs.nixpkgs.follows = "nixos";
      inputs.flake-utils.follows = "digga/flake-utils-plus/flake-utils";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixos";
    };
    digga = {
      url = "github:divnix/digga";
      inputs = {
        nixpkgs.follows = "nixos";
        nixlib.follows = "nixos";
        home-manager.follows = "home";
        # deploy.follows = "deploy";
      };
    };
    sops-nix.url = github:Mic92/sops-nix;
  };

  outputs = { self, nixos, home , digga, ... } @ inputs:
  digga.lib.mkFlake
  {
    inherit self inputs;

    supportedSystems = [ "x86_64-linux"];
    channelsConfig = { allowUnfree = true; };
    channels = rec {
      nixos = {
        # imports = [ (digga.lib.importOverlays ./overlays) ];
        overlays = [
          inputs.sops-nix.overlay
          inputs.nixos-cn.overlay
        ];
      };
    };

    lib = import ./lib { lib = digga.lib // nixos.lib; };

    nixos = {
      hostDefaults = {
        system = "x86_64-linux";
        channelName = "nixos";
        imports = [ (digga.lib.importExportableModules ./modules) ];
        modules = [
          home.nixosModules.home-manager
          inputs.sops-nix.nixosModules.sops
          inputs.nixos-cn.nixosModules.nixos-cn
        ];
      };

      imports = [ (digga.lib.importHosts ./hosts) ];
      hosts = {
        NixOS = { };
      };
      importables = rec {
        profiles = digga.lib.rakeLeaves ./profiles // {
            users = digga.lib.rakeLeaves ./users;
          };
        suites = nixos.lib.fix (suites: {
          core = suites.nixSettings ++ (with profiles; [ programs.tools services.openssh ]);
          nixSettings = with profiles.nix; [ gc settings cachix ];
          base = suites.core ++
          (with profiles; [
            users.root
          ]);
          network = with profiles; [
            networking.common
            networking.resolved
            networking.tools
          ];
          server = (with suites; [
            base
            network
          ]);
        });
      };
    };
  };

}
