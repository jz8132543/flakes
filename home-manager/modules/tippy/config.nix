{ config, inputs, self, pkgs, ... }:
let
  homeDirectory = "/home/tippy";
in
{
  imports = [
    self.nixosModules.impermanence.home-manager.impermanence
  ];
  #sops.secrets.id_ed25519.neededForUsers = true;
  #home.file.".ssh/id_ed25519".source = config.lib.file.mkOutOfStoreSymlink "${config.sops.secrets.id_ed25519.path}";
  # sops.secrets.id_ed25519.path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub".source = pkgs.writeText "pub" ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq i@dora.im
  '';
  home.file."source/nvim".source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.config/nvim";
  home.persistence."/nix/persist/home/tippy" = {
    allowOther = false;
  };
  home.packages = with pkgs; [
    duf
    sops
    home-manager
  ];
}
