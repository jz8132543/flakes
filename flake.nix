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
      # url = "github:divnix/digga";
      url = "github:divnix/digga/?ref=refs/pull/472/head";
      inputs = {
        nixpkgs.follows = "nixos";
        nixlib.follows = "nixos";
        home-manager.follows = "home";
        # deploy.follows = "deploy";
      };
    };
    sops-nix = {
      url = github:Mic92/sops-nix;
      inputs.nixpkgs.follows = "nixos";
    };
    deploy = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixos";
        utils.follows = "digga/flake-utils-plus/flake-utils";
      };
    };
  };

  outputs = { self, nixos, digga, deploy, ... } @ inputs:
  digga.lib.mkFlake
  {
    inherit self inputs;

    supportedSystems = [ "x86_64-linux"];

    channelsConfig = { allowUnfree = true; };
    channels = import ./channels {inherit self inputs;};

    lib = import ./lib { lib = digga.lib // nixos.lib; };

    nixos = ./nixos;

    home = ./home;

    homeConfigurations = digga.lib.mkHomeConfigurations self.nixosConfigurations;

    deploy.nodes =
      let
        inherit (nixos) lib;
        disabledHosts = [  ];
        configs = lib.filterAttrs (name: cfg: !(lib.elem name disabledHosts)) self.nixosConfigurations;
      in
      digga.lib.mkDeployNodes
        configs
        (lib.mapAttrs
          (name: cfg: {
            hostname = "${cfg.config.networking.hostName}.dora.im";
          })
          configs);
    deploy = {
      sshUser = "root";
      user = "tippy";
    };
  };

}
