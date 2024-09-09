{
  inputs,
  lib,
}:
let
  haumea = inputs.haumea.lib;
  loader = lib.const lib.id;
  transformer =
    _cursor: dir:
    assert !(dir ? all);
    dir
    // {
      all = lib.flatten (lib.mapAttrsToList (_: sub: sub.all or [ sub ]) dir);
    };
in
src: haumea.load { inherit src loader transformer; }
