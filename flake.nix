{
  description = "Flamework";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    haumea = {
      url = "github:nix-community/haumea";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/NUR";
    linyinfeng.url = "github:linyinfeng/nur-packages";
    grub2-themes = {
      url = "github:vinceliuice/grub2-themes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; }
      (
        { self, lib, ... }:
        let
          selfLib = import ./lib { inherit inputs lib; };
        in
        {
          debug = true;
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          flake.lib = selfLib;
          imports =
            [
              inputs.flake-parts.flakeModules.easyOverlay
              inputs.linyinfeng.flakeModules.nixpkgs
              inputs.linyinfeng.flakeModules.passthru
              # inputs.linyinfeng.flakeModules.nixago
            ]
            ++ selfLib.buildModuleList ./flake;
        }
      );
}
