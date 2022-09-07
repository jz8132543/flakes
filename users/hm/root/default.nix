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
    hashedPassword = "$6$KXZcD5Rqwx/oRo5A$gK5rEaUDm8eVH.RD8dXNwt0k/FwVbXNZtdSQFMRnSXfOxhw/7ZPnC9pPiRBx21GYxhE/wk8nMGETZgSfR03Ta0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq"
    ];
  };
}
