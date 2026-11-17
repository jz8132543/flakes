{
  lib,
  bitwig-studio6,
  requireFile,
  applyJarPatch ? false,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./sources.json);
  binary =
    asset:
    requireFile {
      inherit (asset) name hash;
      message = ''
        Download this asset outside the build with authenticated GitHub access:

          gh release download ${lib.escapeShellArg manifest.releaseTag} \
            --repo ${lib.escapeShellArg manifest.repository} \
            --pattern ${lib.escapeShellArg asset.name}
          nix-store --add-fixed sha256 ${lib.escapeShellArg asset.name}

        The same file can be imported from assets/bitwig/${manifest.version}/
        in a local checkout of nixos-binary-assets.
        Never put GitHub credentials in Nix expressions or URLs.
      '';
    };
in
bitwig-studio6.overrideAttrs (old: {
  pname = "bitwig-studio";
  inherit (manifest) version;
  src = binary manifest.installer;

  postInstall =
    (old.postInstall or "")
    + lib.optionalString applyJarPatch ''
      test -f "$out/libexec/bin/bitwig.jar"
      install -m644 ${binary manifest.jar} "$out/libexec/bin/bitwig.jar"
    '';

  # Upstream's updater does not manage this version-matched private asset set.
  passthru = (builtins.removeAttrs (old.passthru or { }) [ "updateScript" ]) // {
    inherit applyJarPatch;
  };
})
