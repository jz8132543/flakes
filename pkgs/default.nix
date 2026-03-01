rec {
  mapPackages =
    f:
    with builtins;
    listToAttrs (
      map
        (name: {
          inherit name;
          value = f name;
        })
        (
          filter (v: v != null) (
            attrValues (mapAttrs (k: v: if v == "directory" && k != "_sources" then k else null) (readDir ./.))
          )
        )
    );
  packages = pkgs: mapPackages (name: pkgs.${name});
  overlay =
    final: _prev:
    mapPackages (
      name:
      let
        sources = final.callPackage ./_sources/generated.nix { };
        package = import ./${name};
        source = if builtins.hasAttr name sources then sources.${name} else { };
        args = builtins.intersectAttrs (builtins.functionArgs package) { inherit source; };
      in
      final.callPackage package args
    );
}
