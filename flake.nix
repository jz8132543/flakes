{
  description = "nixos-config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    flake-utils-plus.url = "github:gytis-ivaskevicius/flake-utils-plus";
    nur.url = "github:nix-community/NUR";
    impermanence.url = "github:nix-community/impermanence";
    home = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-cn = {
      url = "github:nixos-cn/flakes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.stable.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    nvfetcher = {
      url = "github:berberman/nvfetcher";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };
  };

outputs = inputs@{ self, nixpkgs, flake-utils-plus, ... }:
let
  this = import ./pkgs;
  hosts = [ "tyo0" "sin0" "ams0" ];
  pkgs = import nixpkgs {
    system = [ "aarch64-linux" "x86_64-linux" ];
  };
in
flake-utils-plus.lib.mkFlake {
  inherit self inputs;

  nixosModules = import ./modules;
  lib = import ./lib { lib = nixpkgs.lib; };

  nixosConfigurations = {
    surface = import ./nixos/surface { system = "x86_64-linux"; inherit self nixpkgs inputs; };
  } // self.colmenaHive.nodes;

  hostDefaults = {
    system = "x86_64-linux";
    modules = [
      inputs.home.nixosModules.home-manager
      inputs.sops-nix.nixosModules.sops
      inputs.nixos-cn.nixosModules.nixos-cn
      inputs.nixos-cn.nixosModules.nixos-cn-registries
      inputs.impermanence.nixosModules.impermanence
    ];
  };

  formatter = pkgs.nixpkgs-fmt;
  packages = this.packages pkgs;
  legacyPackages = pkgs;
  devShells.default = with pkgs; mkShell {
    nativeBuildInputs = [ nvfetcher ];
  };

  hydraJobs = self.packages.x86_64-linux //
  inputs.nixpkgs.lib.genAttrs hosts
    (name: self.colmenaHive.nodes.${name}.config.system.build.install)
  // {
    local = self.nixosConfigurations.local.config.system.build.toplevel;
  };

  colmenaHive = inputs.colmena.lib.makeHive ({
    meta = {
      specialArgs = {
        inherit self inputs;
      };
      nixpkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
      };
    };
  } // inputs.nixpkgs.lib.genAttrs hosts (name: { ... }: {
    deployment = {
      targetHost = "${name}.dora.im";
      tags = [ "normal" ];
    };
    imports = [ ./nixos/${name} ];
  }));
  };
}
