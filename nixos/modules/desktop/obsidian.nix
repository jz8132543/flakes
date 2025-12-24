{
  config,
  lib,
  nixosModules,
  ...
}:

let
  hmUsers = config.home-manager.users;

  mkObsidianMount = user: {
    name = "/home/${user}/.local/XDG/Documents/Notes/Privat";
    value = {
      device = "/var/lib/syncthing/data/Obsidian";
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
