{ pkgs, self, inputs, lib,  ... }: 

let
  a = (lib._.importExportableModules ./modules).exportedModules;
in
{
  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence
  # ] ++ (builtins.map (path: ./${path}) (builtins.attrNames (builtins.readDir ../modules))).exportedModules;
  ] ++ a;

  #modules = [
  #];

  nixpkgs.overlays = [
  ];

}
