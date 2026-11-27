{
  self,
  config,
  inputs,
  lib,
  ...
}:
let
  selfLib = import ../lib { inherit inputs lib; };
  rawNixosModules = selfLib.rake ../nixos/modules;
  nixosModules = rawNixosModules // {
    services = rawNixosModules.services // {
      livekit = import ../nixos/modules/services/livekit-suite;
      rustdesk = {
        default = import ../nixos/modules/services/rustdesk/default.nix;
        server = import ../nixos/modules/services/rustdesk/server.nix;
        relay = import ../nixos/modules/services/rustdesk/relay.nix;
      };
    };
  };

  confNames = lib.filter (
    name: builtins.pathExists (../nixos/hosts + "/${name}")
  ) config.flake.hostNames;

  conf = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = {
        imports = config.flake.colmenaModules.${name};
      };
    }) confNames
  );
in
{
  flake.colmena = {
    meta = {
      description = "my personal machines";
      # This can be overriden by node nixpkgs
      nixpkgs = import inputs.nixpkgs {
        localSystem = {
          system = "x86_64-linux";
        };
      };
      specialArgs = {
        inherit inputs self;
        inherit nixosModules;
      };
    };
  }
  // conf;

  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;
}
