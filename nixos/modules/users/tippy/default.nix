{ config, pkgs, ... }:
let
  name = "tippy";
  homeDirectory = "/home/${name}";
in
{
  users.users.${name} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq" ];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
  security.sudo.wheelNeedsPassword = false;
  home-manager.users.${name} = { hmModules, ... }: {
    imports = hmModules.${name}.all;
    home.global-persistence = {
      enable = true;
      home = homeDirectory;
      directories = [
        "source"
        ".local/share/direnv"
      ];
    };
  };
}
