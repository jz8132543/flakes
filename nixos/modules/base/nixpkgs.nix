{
  inputs,
  getSystem,
  config,
  lib,
  ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
    # inputs.neovim-nightly-overlay.overlay
    # inputs.nixd.overlays.default
    # inputs.nvfetcher.overlays.default
    (
      final: prev:
      let
        inherit (prev.stdenv.hostPlatform) system;
        inherit ((getSystem system).allModuleArgs) inputs';
      in
      {
        inherit (inputs'.nix-gc-s3.packages) nix-gc-s3;
        inherit (inputs'.nix-index-database.packages) nix-index-with-db;
        inherit (inputs'.headscale.packages) headscale;
        clash2sing-box = inputs'.clash2sing-box.packages.default;
        comma = prev.comma.override {
          nix-index-unwrapped = final.nix-index-with-db;
        };
        tailscale = prev.tailscale.overrideAttrs (old: {
          # tailscale = inputs'.tailscale.packages.tailscale.overrideAttrs (old: {
          subPackages = old.subPackages ++ [ "cmd/derper" ] ++ [ "cmd/derpprobe" ];
        });
      }
    )
  ];
  lateFixes =
    _final: _prev:
    {
    };
  lastePackages = [
    (import "${config.lib.self.path}/pkgs").overlay
  ];
in
{
  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = true;
      nvidia.acceptLicense = true;
      binary-caches-parallel-connections = 16;
      permittedInsecurePackages = [
        "openssl-1.1.1w"
        "electron-19.1.9"
        "electron-24.8.6"
        "nix-2.16.2"
      ];
      allowUnfreePackages = [ "terraform" ];
    };
    overlays = packages ++ [ lateFixes ] ++ lastePackages;
  };
}
