{ config, path, pkgs, ... }:
{
  users.users.tippy = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
  };
  security.sudo.wheelNeedsPassword = false;
  environment.persistence."/nix/persist".users.tippy = {
    directories = [
      "source"
      ".local/share/direnv"
    ];
  };
}
