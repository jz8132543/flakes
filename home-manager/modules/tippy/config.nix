{
  config,
  pkgs,
  ...
}: let
  homeDirectory = "/home/tippy";
in {
  sops.secrets."ssh/id_ed25519".path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub".source = pkgs.writeText "pub" ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq i@dora.im
  '';
  home.file."source/nvim".source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.config/nvim";
  home.packages = with pkgs; [
    duf
    sops
    home-manager
  ];
}
