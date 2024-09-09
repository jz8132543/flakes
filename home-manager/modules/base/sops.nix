{
  inputs,
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
      keyFile = "/var/lib/sops-nix/key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };
}
