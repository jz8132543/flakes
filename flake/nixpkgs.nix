{ inputs
, ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
  ];
in
{
  flake.nixpkgs = {
    config = {
      allowUnfree = true;
    };
    overlays = packages;
  };
}
