{ inputs
, ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
  ];

  lateFixes = final: prev:
    {
      tailscale-derp = final.tailscale.overrideAttrs (old: {
        subPackages = old.subPackages ++ [ "cmd/derper" ];
      });
    };
in
{
  flake.nixpkgs = {
    config = {
      allowUnfree = true;
    };
    overlays = packages ++ lateFixes;
  };
}
