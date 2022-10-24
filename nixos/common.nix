{ pkgs, self, inputs, lib,  ... }: 

{
    inherit (self.lib) _;
  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence
  ] ++ _.mapModulesRec' ../modules import;

  nixpkgs.overlays = [
  ];

}
