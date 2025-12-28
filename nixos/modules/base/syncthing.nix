{
  config,
  lib,
  nixosModules,
  ...
}:

let
  hmUsers = config.home-manager.users;

  mkObsidianMount = user: {
    name = "/home/${user}/Sync";
    value = {
      device = "/var/lib/syncthing/data";
      options = [
        "bind"
        "nofail"
        "x-systemd.requires=syncthing.service"
      ];
    };
  };
in
{
  imports = [
    nixosModules.services.syncthing
  ];

  fileSystems = lib.listToAttrs (map mkObsidianMount (builtins.attrNames hmUsers));
}
