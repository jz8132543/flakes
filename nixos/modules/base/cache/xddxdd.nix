{
  lib,
  config,
  ...
}:
{
  nix.settings.substituters =
    if !config.environment.isCN then lib.mkForce [ "https://xddxdd.cachix.org" ] else [ ];
  nix.settings.trusted-public-keys = [
    "xddxdd.cachix.org-1:ay1HJyNDYmlSwj5NXQG065C8LfoqqKaTNCyzeixGjf8="
  ];
}
