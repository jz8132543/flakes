{inputs, ...}: let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.neovim-nightly-overlay.overlay
  ];
  lateFixes = final: prev: {
    tailscale-derp = final.tailscale.overrideAttrs (old: {
      subPackages = old.subPackages ++ ["cmd/derper"];
    });
  };
in {
  nixpkgs = {
    config = {
      allowUnfree = true;
    };
    overlays = packages ++ [lateFixes];
  };
}
