{ config, inputs, self, ... }:
let
  homeDirectory = "/home/tippy";
in
{
  imports = [
    self.nixosModules.impermanence.home-manager.impermanence
  ];
  home.file."source/nvim".source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.config/nvim";
}