{ config, ... }:

let
  name = "root";
  homeDirectory = "/home/${name}";
  aws_link = config.sops.secrets.s3_credentials.path;
in{
  home-manager.users.${name} = { config, suites, ... }: {
    home.file.".aws/credentials".source =
      config.lib.file.mkOutOfStoreSymlink aws_link;
  };
  users.users.${name} = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq"
    ];
  };
}
