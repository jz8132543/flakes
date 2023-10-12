{
  inputs,
  getSystem,
  config,
  lib,
  ...
}: let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.neovim-nightly-overlay.overlay
    inputs.nixd.overlays.default
    inputs.alejandra.overlay
    inputs.nvfetcher.overlays.default
    (
      final: prev: let
        inherit (prev.stdenv.hostPlatform) system;
        inherit ((getSystem system).allModuleArgs) inputs';
      in {
        nix-gc-s3 = inputs'.nix-gc-s3.packages.nix-gc-s3;
        tuic = inputs'.latest.legacyPackages.tuic;
      }
    )
  ];
  lateFixes = final: prev: {
    tailscale-derp = final.tailscale.overrideAttrs (old: {
      subPackages = old.subPackages ++ ["cmd/derper"];
    });
  };
  lastePackages = [
    (import "${config.lib.self.path}/pkgs").overlay
  ];
in {
  nixpkgs = {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "openssl-1.1.1w"
        "electron-19.1.9"
      ];
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "terraform"
      ];

    };
    overlays = packages ++ [lateFixes] ++ lastePackages;
  };
}
