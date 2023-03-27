{
  description = "Flamework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    flake-utils.url = "github:numtide/flake-utils";
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
      inputs.utils.follows = "flake-utils";
    };
    spicetify-nix = {
      url = github:the-argus/spicetify-nix;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    nur.url = "github:nix-community/NUR";
    dora = {
      url = "github:a1ca7raz/nurpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    grub2-themes = {
      url = "github:vinceliuice/grub2-themes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
  };

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      utils = import ./utils lib self;
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config = {
          allowUnfree = true;
        };
        overlays = utils.loader.overlays ++ [
          inputs.nur.overlay
        ];
      };
    in
    {
      legacyPackages = pkgs;
      packages = pkgs;

      devShells.x86_64-linux.default = with pkgs; mkShell {
        nativeBuildInputs = [ colmena nvfetcher ];
      };

      nixosModules = utils.module // utils.loader.nixosModules // (with inputs; {
        sops = sops-nix.nixosModules.sops;
        impermanence = impermanence.nixosModules;
        disko = disko.nixosModules.disko;
        home = home-manager.nixosModules.home-manager;
        lanzaboote = lanzaboote.nixosModules.lanzaboote;
        nur = inputs.nur.nixosModules.nur;
        hyprland = inputs.hyprland.nixosModules.default;
      });

      nixosConfigurations = utils.loader.profiles.nixosConfigurations;

      colmena = utils.loader.profiles.colmena;
    };
}
