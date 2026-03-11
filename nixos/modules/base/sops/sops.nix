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
      # Image builds run `nixos-install` inside a VM and execute activation scripts.
      # When the SOPS key file lives on /persist (impermanence), it may not exist yet,
      # causing the install to fail. Use a systemd unit instead so secrets are
      # installed at boot/switch time once mounts and keys are in place.
      useSystemdActivation = lib.mkDefault true;
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

    systemd.tmpfiles.rules = lib.optional config.environment.global-persistence.enable "d /persist/var/lib/sops-nix 0755 tippy users -";
  };
}
