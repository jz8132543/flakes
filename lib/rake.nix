{
  inputs,
  lib,
}: let
  haumea = inputs.haumea.lib;
  loader = lib.const lib.id;
  transformer = _cursor: dir:
    assert ! (dir ? all);
      dir
      // {
        all = lib.flatten (lib.mapAttrsToList
          (_: sub:
            if sub ? all
            then sub.all
            else [sub])
          dir);
      };
in
  src:
    haumea.load {inherit src loader transformer;}
