{
  inputs,
  lib,
  osConfig,
  ...
}:
{
  imports = [
    inputs.sops-nix.homeManagerModule
  ];
  sops = {
    defaultSopsFile = osConfig.sops-file.get "common.yaml";
    age = {
      keyFile = lib.mkDefault "/var/lib/sops-nix/key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };
}
