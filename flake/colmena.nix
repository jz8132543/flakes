{
  self,
  config,
  inputs,
  lib,
  ...
}:
let
  selfLib = import ../lib { inherit inputs lib; };
  nixosModules = selfLib.rake ../nixos/modules;

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
      nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
      specialArgs = {
        inherit inputs self;
        inherit (config.flake) matrixRtcHosts;
        inherit nixosModules;
      };
    };
  }
  // conf;

  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;
}
