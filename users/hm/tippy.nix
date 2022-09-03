{ config, suites, ... }:
let
  name = "tippy";
  homeDirectory = "/home/${name}";
  link = config.sops.secrets.id_ed25519.path;
in {
  sops.secrets.id_ed25519 = {
    format = "binary";
    owner = config.users.users.${name}.name;
    group = config.users.users.${name}.group;
    sopsFile = config.sops.secretsDir + /id_ed25519.keytab;
  };
  imports = suites.base;
  home.file.".ssh/id_ed25519".source =
    config.lib.file.mkOutOfStoreSymlink link;
  home.global-persistence = {
    enable = true;
    home = homeDirectory;
    directories = [
      "Source"
    ];
  };
}
