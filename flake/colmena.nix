{
  self,
  inputs,
  lib,
  ...
}:
let
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
      nodeNixpkgs = builtins.mapAttrs (_name: value: value.pkgs) conf;
      nodeSpecialArgs = builtins.mapAttrs (_name: value: value._module.specialArgs) conf;
    };
  }
  // builtins.mapAttrs (name: _value: { imports = self.colmenaModules.${name}; }) conf;

  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;
}
