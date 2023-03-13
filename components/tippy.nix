{ config, path, pkgs, ... }:
{
  users.users.tippy = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
    passwordFile = config.sops.secrets.passwd.path;
  };
  sops.secrets.passwd.neededForUsers = true;
  security.sudo.wheelNeedsPassword = false;
  environment.persistence."/nix/persist".users.tippy = {
    directories = [
      "source"
      ".local/share/direnv"
    ];
  };
}
