{
  inputs,
  lib,
  self,
}:
[
  inputs.sops-nix.overlays.default
  inputs.rust-overlay.overlays.default
  inputs.antigravity-nix.overlays.default
  inputs.chinese-fonts-overlay.overlays.default
  (
    _final: prev:
    {
      tailscale = prev.tailscale.overrideAttrs (old: {
        subPackages = [
          "cmd/tailscaled"
          "cmd/derper"
          "cmd/stunc"
          "cmd/hello"
        ];
        postInstall = lib.strings.concatStrings [
          "cp $out/bin/derper $out/bin/derp && "
          (old.postInstall or "")
        ];
      });
    }
    // (self.lib.maybeAttrByPath "comma-with-db" inputs [
      "nix-index-database"
      "packages"
      prev.stdenv.hostPlatform.system
      "comma-with-db"
    ])
  )
  (import "${self}/pkgs").overlay
]
