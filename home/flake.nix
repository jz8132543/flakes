{
  description = "Home Manager configuration of Tippy";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations.tippy = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          sops-nix.nixosModules.sops
          ./home.nix
        ];
      };
    };
}
