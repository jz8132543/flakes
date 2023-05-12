{ config, pkgs, ... }:
{
  users.users.tippy = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    # openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
  # sops.secrets.passwd.neededForUsers = true;
  security.sudo.wheelNeedsPassword = false;
  environment.persistence."/nix/persist".users.tippy = {
    directories = [
      "source"
      ".local/share/direnv"
    ];
  };
}
