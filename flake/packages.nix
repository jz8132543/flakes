{ ... }:
{
  perSystem =
    {
      pkgs,
      self',
      lib,
      ...
    }:
    {
      packages = {
        inherit (pkgs) nixos-anywhere;
      };
      checks = lib.mapAttrs' (name: p: lib.nameValuePair "package/${name}" p) self'.packages;
    };
}
