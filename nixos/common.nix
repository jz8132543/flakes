{ pkgs, self, inputs, ... }: {

  imports = [
    inputs.home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.nixos-cn.nixosModules.nixos-cn-registries
    inputs.impermanence.nixosModules.impermanence

    self.nixosModules.base

  ];

  nixpkgs.overlays = [
  ];

}
