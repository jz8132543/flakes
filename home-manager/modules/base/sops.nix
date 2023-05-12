{ inputs, pkgs, config, ... }:
{
  imports = [
    inputs.sops-nix.homeManagerModule
  ];
  sops = {
    age = {
      keyFile = "/var/lib/sops-nix/key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };
}
