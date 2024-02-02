{
  lib,
  config,
  ...
}: {
  nix.settings = {
    substituters =
      if !config.environment.isCN
      then
        lib.mkForce [
          "https://nix-community.cachix.org"
        ]
      else [];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
