{ inputs
, getSystem
, lib
, ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.nixos-cn.overlay
  ];
in
{
  nixpkgs = {
    config = {
      allowUnfree = true;
    };
    overlays = packages;
  };
}
