{
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  cfg = config.nixpkgs;
in
{
  options.nixpkgs = {
    config = lib.mkOption {
      type = with lib.types; attrsOf raw;
      default = { };
    };
    overlays = lib.mkOption {
      type = with lib.types; listOf raw;
      default = [ ];
    };
  };
  config = {
    nixpkgs.overlays = lib.mkDefault (
      import ../lib/overlays.nix {
        inherit inputs lib self;
      }
    );

    perSystem =
      { system, ... }:
      {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          inherit (cfg) config overlays;
        };
      };
  };
}
