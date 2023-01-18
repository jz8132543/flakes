{ config, lib, ... }:

{
  nix = {
    settings.substituters = [ "https://xddxdd.cachix.org" ];
    settings.trusted-public-keys = [
      "xddxdd.cachix.org-1:ay1HJyNDYmlSwj5NXQG065C8LfoqqKaTNCyzeixGjf8="
    ];
  };
}
