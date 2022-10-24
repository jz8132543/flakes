{ pkgs, self, inputs, lib,  ... }: 

{
  inherit (lib._);
  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence

    # self.nixosModules
  # ] ++ lib._.mapModulesRec' ../modules import;
  ];

  nixpkgs.overlays = [
  ];

}
