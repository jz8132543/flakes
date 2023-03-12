{ config, inputs, self, pkgs, ... }:
let
  homeDirectory = "/home/tippy";
in
{
  imports = [
    self.nixosModules.impermanence.home-manager.impermanence
  ];
  home.file."source/nvim".source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.config/nvim";
  home.file.".ssh/id_ed25519" = ${config.sops.secrets.id_ed25519.path};
  home.packages = with pkgs; [
    duf
  ];
}
