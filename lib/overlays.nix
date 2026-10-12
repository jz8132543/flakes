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
    qdrant = inputs.latest.legacyPackages.${final.system}.qdrant;
  })
  (import "${self}/pkgs").overlay
]
