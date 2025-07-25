{
  self,
  inputs,
  ...
}:
let
  conf = self.nixosConfigurations;
in
{
  flake.colmena = {
    meta = {
      description = "my personal machines";
      # This can be overriden by node nixpkgs
      nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      nodeNixpkgs = builtins.mapAttrs (_name: value: value.pkgs) conf;
      nodeSpecialArgs = builtins.mapAttrs (_name: value: value._module.specialArgs) conf;
    };
  } // builtins.mapAttrs (_name: value: { imports = value._module.args.modules; }) conf;
}
