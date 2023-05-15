{ config
, lib
, ...
}:
let
  inherit (config.networking) hostName;
in
{
  options.sops-file = {
    directory = lib.mkOption {
      type = lib.types.path;
    };
    get = lib.mkOption {
      type = with lib.types; functionTo path;
    };
    host = lib.mkOption {
      type = lib.types.path;
    };
    terraform = lib.mkOption {
      type = lib.types.path;
    };
  };
  config = {
    sops-file.directory = lib.mkDefault ../../../secrets;
    sops-file.get = p: "${config.sops-file.directory}/${p}";
    sops-file.host = config.sops-file.get "hosts/${hostName}.yaml";
    sops-file.terraform = config.sops-file.get "terraform/hosts/${hostName}.yaml";

    sops.gnupg.sshKeyPaths = [ ];
    sops.age = {
      sshKeyPaths = [ ];
      keyFile = "/var/lib/sops-nix/key";
    };
  };
}

