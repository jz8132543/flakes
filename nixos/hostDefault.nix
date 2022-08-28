{ inputs, self, ... }:
with inputs; {
  system = "x86_64-linux";
  channelName = "nixos";
  imports = [ (digga.lib.importExportableModules ../modules) ];
  modules = [
    home.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-cn.nixosModules.nixos-cn
    inputs.impermanence.nixosModules.impermanence
  ];
}
