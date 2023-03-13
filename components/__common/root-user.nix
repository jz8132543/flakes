{ config, pkgs, path, ... }:
{
  sops.secrets.passwd.neededForUsers = true;
  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
    passwordFile = config.sops.secrets.passwd.path;
  };
}
