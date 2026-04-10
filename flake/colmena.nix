{
  self,
  inputs,
  lib,
  ...
}:
let
  selfLib = import ../lib { inherit inputs lib; };
  nixosModules = selfLib.rake ../nixos/modules;

  conf = lib.filterAttrs (
    name: _value: builtins.pathExists (../nixos/hosts + "/${name}")
  ) self.nixosConfigurations;
in
{
  flake.colmena = {
    meta = {
      description = "my personal machines";
      # This can be overriden by node nixpkgs
      nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
      specialArgs = {
        inherit inputs self;
        inherit nixosModules;
      };
    };
  }
  // builtins.mapAttrs (name: _value: { imports = self.colmenaModules.${name}; }) conf;

  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;
}
