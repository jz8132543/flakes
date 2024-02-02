{
  lib,
  config,
  ...
}: {
  nix.settings.substituters =
    if !config.environment.isCN
    then lib.mkForce ["https://cache.nixos.org/"]
    else "";
}
