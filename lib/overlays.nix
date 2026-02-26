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
  (final: prev: {
    qt6Packages = prev.qt6Packages.overrideScope (
      _qt6Final: qt6Prev: {
        libsForQt5 = (qt6Prev.libsForQt5 or (prev.libsForQt5.overrideScope (_: _: { }))).overrideScope (
          _qt5Final: _qt5Prev: {
            fcitx5-qt = null;
          }
        );
      }
    );

    inherit (final.qt6Packages) fcitx5-qt;

    fcitx5-configtool = prev.fcitx5-configtool.override { kcmSupport = false; };

    fcitx5-chinese-addons = prev.fcitx5-chinese-addons.override {
      enableCloudPinyin = false;
      enableOpencc = false;
      qtwebengine = null;
    };
  })
  (import "${self}/pkgs").overlay
]
