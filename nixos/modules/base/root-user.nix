{ config, pkgs, ... }:
{
  # sops.secrets.passwd.neededForUsers = true;
  users.users.root = {
    shell = pkgs.zsh;
    # openssh.authorizedKeys.keys = import /${path}/config/sshkeys.nix;
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
}
