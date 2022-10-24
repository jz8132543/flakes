{ pkgs, self, inputs, lib,  ... }: 

{
  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence
    (lib._.importExportableModules ../modules)
  ];

  nixpkgs.overlays = [
  ];

}
