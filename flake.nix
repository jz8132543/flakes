{
description = "nixos-config";

inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  nixos-hardware.url = "github:nixos/nixos-hardware";
  flake-utils.url = "github:numtide/flake-utils";
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
  nvfetcher = {
    url = "github:berberman/nvfetcher";
    inputs = {
      nixpkgs.follows = "nixpkgs";
    };
  };
  digga.url = "github:divnix/digga";
};

outputs = inputs@{ self, nixpkgs, ... }:
let
  this = import ./pkgs;
  hosts = [ "tyo0" "sin0" "ams0" "surface" ];
in
inputs.flake-utils.lib.eachSystem [ "aarch64-linux" "x86_64-linux" ]
(
  system:
  let
    pkgs = import nixpkgs {
      inherit system;
    };
    lib = import ./lib { inherit pkgs inputs; lib = nixpkgs.lib; };
    inherit (lib._) mapModules mapModulesRec';
  in
  {
    formatter = pkgs.nixpkgs-fmt;
    packages = this.packages pkgs;
    legacyPackages = pkgs;
    nixosModules = (mapModulesRec' ./modules import);
  }
) // {
  nixosConfigurations = self.colmenaHive.nodes;
  home-manager = self.nixosModules.home;

  hydraJobs = self.packages.x86_64-linux //
  inputs.nixpkgs.lib.genAttrs hosts
    (name: self.colmenaHive.nodes.${name}.config.system.build.install);

  colmenaHive = inputs.colmena.lib.makeHive ({
    meta = {
      specialArgs = {
        inherit self inputs;
        lib = import ./lib { inherit inputs; pkgs = nixpkgs; lib = nixpkgs.lib; };
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
      # (lib._.importExportableModules ./modules).exportedModules;
      # builtins.map (path: if (builtins.pathExists ("${self}" + path + "/default.nix")) then "${self}/modules/${path}" else "${self}/modules") (builtins.attrNames (builtins.readDir ./modules));
  }));
  };
}
