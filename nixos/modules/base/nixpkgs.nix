{inputs, ...}: let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.neovim-nightly-overlay.overlay
    inputs.attic.overlays.default
  ];
  lateFixes = final: prev: {
    tailscale-derp = final.tailscale.overrideAttrs (old: {
      subPackages = old.subPackages ++ ["cmd/derper"];
    });
    tailscale-derpprobe = final.tailscale.overrideAttrs (old: {
      subPackages = old.subPackages ++ ["cmd/derpprobe"];
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
