{ inputs, self, ... }:
with inputs; {
  system = "x86_64-linux";
  channelName = "nixos";
  imports = [ (digga.lib.importExportableModules ../modules) ];
  modules = [
    home.nixosModules.home-manager
    sops-nix.nixosModules.sops
    nixos-cn.nixosModules.nixos-cn
    nixos-cn.nixosModules.nixos-cn-registries
    impermanence.nixosModules.impermanence
    grub2-themes.nixosModule
  ];
}
