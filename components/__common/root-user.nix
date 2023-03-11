{ config, pkgs, path, ... }:
{
  users.users.root = {
    shell = pkgs.zsh;

    openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
  };
}
