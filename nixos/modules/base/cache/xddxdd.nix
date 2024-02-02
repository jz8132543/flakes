{lib, ...}: {
  nix.settings.substituters = lib.mkForce ["https://xddxdd.cachix.org"];
  nix.settings.trusted-public-keys = ["xddxdd.cachix.org-1:ay1HJyNDYmlSwj5NXQG065C8LfoqqKaTNCyzeixGjf8="];
}
