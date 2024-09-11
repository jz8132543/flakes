{
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.networking) hostName;
in
{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
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
    sops-file.directory = lib.mkDefault ../../../../secrets;
    sops-file.get = p: "${config.sops-file.directory}/${p}";
    sops-file.host = config.sops-file.get "hosts/${hostName}.yaml";
    sops-file.terraform = config.sops-file.get "terraform/hosts/${hostName}.yaml";

    sops = {
      defaultSopsFile = config.sops-file.get "common.yaml";
      gnupg.sshKeyPaths = [ ];
      age = {
        sshKeyPaths = [ ];
        keyFile = lib.mkDefault (
          if config.environment.global-persistence.enable then
            "/persist/var/lib/sops-nix/key"
          else
            "/var/lib/sops-nix/key"
        );
      };
    };
  };
}
