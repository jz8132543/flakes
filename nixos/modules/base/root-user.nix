{
  config,
  pkgs,
  ...
}:
{
  users.users.root = {
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [ config.lib.self.data.ssh.i ];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
}
