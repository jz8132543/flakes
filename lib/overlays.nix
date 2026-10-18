{
  inputs,
  self,
  ...
}:
[
  inputs.sops-nix.overlays.default
  inputs.rust-overlay.overlays.default
  inputs.chinese-fonts-overlay.overlays.default
  (
    _final: prev:
    {
    }
    // (self.lib.maybeAttrByPath "comma-with-db" inputs [
      "nix-index-database"
      "packages"
      prev.stdenv.hostPlatform.system
      "comma-with-db"
    ])
  )
  (final: prev: {
    wpsoffice-cn = prev.symlinkJoin {
      name = "${prev.wpsoffice-cn.name or "wpsoffice-cn"}-no-scale";
      inherit (prev.wpsoffice-cn) version meta;
      paths = [ prev.wpsoffice-cn ];
      nativeBuildInputs = [ prev.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --set QT_AUTO_SCREEN_SCALE_FACTOR 0 \
              --set QT_ENABLE_HIGHDPI_SCALING 0 \
              --set QT_SCALE_FACTOR 1
          fi
        done
      '';
    };

    ms365 =
      if (inputs ? office365) && (prev.stdenv.hostPlatform.system == "x86_64-linux") then
        let
          orig = inputs.office365.packages.${prev.stdenv.hostPlatform.system}.default;
        in
        prev.symlinkJoin {
          name = "${orig.name or "ms365"}-gnome-auto-dpi";
          inherit (orig) meta;
          paths = [ orig ];
          nativeBuildInputs = [ prev.makeWrapper ];
          postBuild = ''
            for bin in $out/bin/ms365*; do
              if [ -f "$bin" ] && [ -x "$bin" ]; then
                wrapProgram "$bin" \
                  --run '
                    if [ -z "$MS365_DPI" ]; then
                      scale=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | sed -E -n "s/.*\[\([0-9]+, [0-9]+, ([0-9.]+), uint32 [0-9]+, (true|false).*/\1/p")
                      if [ -z "$scale" ]; then
                        scale=$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null | awk "{print \$2}")
                        [ "$scale" = "0" ] || [ -z "$scale" ] && scale=1.0
                      fi
                      export MS365_DPI=$(awk -v s="$scale" "BEGIN { dpi = int(96 * s + 0.5); if (dpi >= 192) dpi = 180; print dpi }")
                    fi
                  '
              fi
            done
          '';
        }
      else
        null;

    # perlPackages = prev.perlPackages.overrideScope (
    #   _pfinal: _pprev: {
    #     URIws = prev.emptyDirectory;
    #   }
    # );
    #
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        pysaml2 = pyPrev.pysaml2.overridePythonAttrs (_: {
          doCheck = false;
        });
      })
    ];

    matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overrideAttrs (_old: {
      doCheck = false;
      dontCheck = true;
      checkPhase = "";
      doInstallCheck = false;
      dontInstallCheck = true;
      installCheckPhase = "";
      nativeCheckInputs = [ ];
    });

    matrix-synapse = prev.matrix-synapse.override {
      inherit (final) matrix-synapse-unwrapped;
    };
    qdrant = inputs.nixos-2605.legacyPackages.${final.system}.qdrant;
  })
  (import "${self}/pkgs").overlay
]
