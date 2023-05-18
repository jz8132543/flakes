{ config, pkgs, ... }:
{
  users.users.root = {
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq" ];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
}
