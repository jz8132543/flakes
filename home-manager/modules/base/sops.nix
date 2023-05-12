{ inputs, pkgs, ... }:
{
  imports = [
    inputs.sops-nix.homeManagerModules
  ];
  sops = {
    age = {
      keyFile = "/var/lib/sops-nix/key";
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };
}
