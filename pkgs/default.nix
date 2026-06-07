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
            attrValues (
              mapAttrs (
                k: v: if v == "directory" && k != "_sources" && pathExists ./${k}/default.nix then k else null
              ) (readDir ./.)
            )
          )
        )
    );
  packages = pkgs: mapPackages (name: pkgs.${name});
  overlay = final: _prev: mapPackages (name: final.callPackage (import ./${name}) { });
}
