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
        lldap = inputs'.latest.legacyPackages.lldap;
        nix-index-with-db = inputs'.nix-index-database.packages.nix-index-with-db;
        comma = prev.comma.override {
          nix-index-unwrapped = final.nix-index-with-db;
        };
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
      binary-caches-parallel-connections = 16;
      permittedInsecurePackages = [
        "openssl-1.1.1w"
        "electron-19.1.9"
        "electron-24.8.6"
      ];
    };
    overlays = packages ++ [lateFixes] ++ lastePackages;
  };
}
