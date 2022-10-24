{ pkgs, self, inputs, lib,  ... }: 

{
  imports = [
    # (lib._.importExportableModules ../modules)
  ] ++ (builtins.map (path: ./${path}) (builtins.attrNames (builtins.readDir ../modules)));

  #modules = [
  #  inputs.home.nixosModules.home-manager
  #  inputs.sops-nix.nixosModules.sops
  #  inputs.nixos-cn.nixosModules.nixos-cn
  #  inputs.nixos-cn.nixosModules.nixos-cn-registries
  #  inputs.impermanence.nixosModules.impermanence
  #];

  nixpkgs.overlays = [
  ];

}
