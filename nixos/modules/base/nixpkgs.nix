{
  inputs,
  getSystem,
  config,
  lib,
  ...
}: let
  packages = [
    (import "${config.lib.self.path}/pkgs").overlay
    inputs.sops-nix.overlays.default
    inputs.neovim-nightly-overlay.overlay
    inputs.attic.overlays.default
    inputs.nixd.overlays.default
    inputs.clash-meta.overlay
    (
      final: prev: let
        inherit (prev.stdenv.hostPlatform) system;
        inherit ((getSystem system).allModuleArgs) inputs';
      in
        {
          nix-gc-s3 = inputs'.nix-gc-s3.packages.nix-gc-s3;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          hydra-master = inputs'.hydra.packages.default;
        }
    )
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
