{
  inputs,
  getSystem,
  config,
  lib,
  self,
  ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.neovim-nightly-overlay.overlays.default
    inputs.rust-overlay.overlays.default
    inputs.chinese-fonts-overlay.overlays.default
    (
      _final: prev:
      let
        inherit (prev.stdenv.hostPlatform) system;
        inherit ((getSystem system).allModuleArgs) inputs';
      in
      {
        # inherit (inputs'.nix-gc-s3.packages) nix-gc-s3;
        # inherit (inputs'.headscale.packages) headscale;
        # clash2sing-box = inputs'.clash2sing-box.packages.default;
        tailscale = prev.tailscale.overrideAttrs (old: {
          # tailscale = inputs'.tailscale.packages.tailscale.overrideAttrs (old: {
          # subPackages = old.subPackages ++ [ "cmd/derper" ] ++ [ "cmd/derpprobe" ];
          subPackages = [
            "cmd/tailscaled"
            "cmd/derper"
            "cmd/stunc"
            "cmd/hello"
          ];
          postInstall = lib.strings.concatStrings [
            "cp $out/bin/derper $out/bin/derp && "
            old.postInstall
          ];
        });
        inherit (inputs'.latest.legacyPackages) nextcloud;
      }
      // (self.lib.maybeAttrByPath "comma-with-db" inputs [
        "nix-index-database"
        "packages"
        system
        "comma-with-db"
      ])
    )
  ];
  lateFixes = _final: _prev: { };
  lastePackages = [ (import "${config.lib.self.path}/pkgs").overlay ];
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
        "electron-27.3.11"
        "nix-2.24.5"
      ];
      allowUnfreePackages = [
        "terraform"
        "vscode"
      ];
    };
    overlays = packages ++ [ lateFixes ] ++ lastePackages;
  };
}
