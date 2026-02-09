{
  self,
  lib,
  inputs,
  ...
}:
let
  # Function to generate nodes for deploy-rs
  # It merges nixosConfigurations and homeConfigurations by hostname
  nodes =
    let
      # System nodes from nixosConfigurations
      nixosNodes = lib.mapAttrs (name: cfg: {
        hostname = name;
        profiles.system = {
          sshUser = "root";
          user = "root";
          path = inputs.deploy-rs.lib.${cfg.pkgs.stdenv.hostPlatform.system}.activate.nixos cfg;
          # Disable profile-level checks
          check = false;
        };
      }) self.nixosConfigurations;

      # Home nodes from homeConfigurations
      # HM keys are in "user@host" format
      hmNodes = lib.concatMapAttrs (
        key: cfg:
        let
          parts = lib.splitString "@" key;
          user = lib.elemAt parts 0;
          host = lib.elemAt parts 1;
        in
        {
          ${host} = {
            hostname = host;
            profiles."user-${user}" = {
              sshUser = user;
              inherit user;
              path = inputs.deploy-rs.lib.${cfg.pkgs.stdenv.hostPlatform.system}.activate.home-manager cfg;
              # Disable profile-level checks
              check = false;
            };
          };
        }
      ) self.homeConfigurations;
    in
    lib.recursiveUpdate nixosNodes hmNodes;
in
{
  flake = {
    deploy = {
      autoRollback = true;
      magicRollback = true;

      # Disable default evaluation of flake.checks
      checks = { };

      inherit nodes;
    };
  };
  perSystem =
    {
      inputs',
      ...
    }:
    {
      devshells.default = {
        commands = [
          {
            package = inputs'.deploy-rs.packages.deploy-rs;
            name = "deploy";
            category = "deploy";
          }
        ];
      };
    };
}
