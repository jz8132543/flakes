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
    nur.url = "github:nix-community/NUR";
    digga = {
      # url = "github:divnix/digga";
      url = "github:divnix/digga/?ref=refs/pull/472/head";
      inputs = {
        nixpkgs.follows = "nixos";
        nixlib.follows = "nixos";
        home-manager.follows = "home";
        deploy.follows = "deploy";
      };
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixos";
    };
    deploy = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixos";
        utils.follows = "digga/flake-utils-plus/flake-utils";
      };
    };
    impermanence.url = "github:nix-community/impermanence";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixos, digga, deploy, ... }@inputs:
    digga.lib.mkFlake {
      inherit self inputs;

      supportedSystems = [ "x86_64-linux" ];

      channelsConfig = { allowUnfree = true; };
      channels = import ./channels { inherit self inputs; };

      lib = import ./lib { lib = digga.lib // nixos.lib; };

      nixos = ./nixos;

      home = ./home;

      homeConfigurations =
        digga.lib.mkHomeConfigurations self.nixosConfigurations;

      templates = {
        default = self.templates.project;
        project.path = ./templates/project;
      };

      deploy.nodes = let
        inherit (nixos) lib;
        disabledHosts = [ ];
        configs = lib.filterAttrs (name: cfg: !(lib.elem name disabledHosts))
          self.nixosConfigurations;
      in digga.lib.mkDeployNodes configs (lib.mapAttrs
        (name: cfg: { hostname = "${cfg.config.networking.hostName}.dora.im"; })
        configs);
      deploy = {
        sshUser = "root";
        user = "tippy";
      };
      outputsBuilder = channels:
      let
        pkgs = channels.nixos;
        inherit (pkgs) system lib;
      in
      {
        checks =
          deploy.lib.${system}.deployChecks self.deploy //
          (
            lib.foldl lib.recursiveUpdate { }
              (lib.mapAttrsToList
                (host: cfg:
                  lib.optionalAttrs (cfg.pkgs.system == system)
                    { "toplevel-${host}" = cfg.config.system.build.toplevel; })
                self.nixosConfigurations)
          ) // (
            lib.mapAttrs'
              (name: drv: lib.nameValuePair "package-${name}" drv)
              self.packages.${system}
          ) // {
            devShell = self.devShell.${system};
          };

          hydraJobs = self.checks.${system} // {
            all-checks = pkgs.linkFarm "all-checks"
              (lib.mapAttrsToList (name: drv: { inherit name; path = drv; })
                self.checks.${system});
          };
      };
    };

}
