{ config, ... }:

let
  name = "root";
  homeDirectory = "/home/${name}";
in{
  users.users.${name} = {
    initialPassword = "$6$KXZcD5Rqwx/oRo5A$gK5rEaUDm8eVH.RD8dXNwt0k/FwVbXNZtdSQFMRnSXfOxhw/7ZPnC9pPiRBx21GYxhE/wk8nMGETZgSfR03Ta0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq"
    ];
  };
}
