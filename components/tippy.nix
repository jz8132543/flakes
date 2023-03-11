{ config, path, pkgs, ... }:
{
  users.users.tippy = {
    isNormalUser = true;

    shell = pkgs.fish;
    extraGroups = [ "wheel" ];

    openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
  };
}
