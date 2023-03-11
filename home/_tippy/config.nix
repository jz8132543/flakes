{ config, ... }:
let
  homeDirectory = "/home/tippy";
in
{
  home.file."source/nvim".source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.config/nvim";
  environment.etc."nixos".source = "${homeDirectory}/source/flakes";
  security.sudo.wheelNeedsPassword = false;
  environment.persistence."/persist".users.tippy = {
    directories = [
      "source"
      ".local/share/direnv"
      ".local/share/containers"
    ];
  };
}
