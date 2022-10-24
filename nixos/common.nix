{ pkgs, self, inputs, lib,  ... }: 

{
  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence
  # ] ++ (builtins.map (path: ./${path}) (builtins.attrNames (builtins.readDir ../modules))).exportedModules;
  ] ++ (builtins.map (path: ../modules/${path}) (builtins.attrNames (builtins.readDir ../modules)));

  #modules = [
  #];

  nixpkgs.overlays = [
  ];

}
