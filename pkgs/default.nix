rec {
  # 遍历自动发现顶级目录与分类子目录 (obsidian/, zotero/ 等) 下所有含有 default.nix 的包
  findPackages =
    dir:
    with builtins;
    let
      entries = readDir dir;
      isDir = name: (getAttr name entries == "directory") && (name != "_sources");

      topLevelDirs = filter isDir (attrNames entries);

      processDir =
        d:
        if pathExists (dir + "/${d}/default.nix") then
          [
            {
              name = d;
              subName = d;
              relPath = d;
              category = null;
            }
          ]
        else
          let
            subEntries = readDir (dir + "/${d}");
            subDirs = filter (
              sd:
              (getAttr sd subEntries == "directory")
              && (sd != "_sources")
              && (pathExists (dir + "/${d}/${sd}/default.nix"))
            ) (attrNames subEntries);
          in
          map (
            sd:
            let
              flatName =
                if (builtins.substring 0 (builtins.stringLength "${d}-") sd) == "${d}-" then sd else "${d}-${sd}";
            in
            {
              name = flatName;
              subName = sd;
              relPath = "${d}/${sd}";
              category = d;
            }
          ) subDirs;

      allPkgs = concatLists (map processDir topLevelDirs);
    in
    allPkgs;

  packages =
    pkgs:
    let
      pkgList = findPackages ./.;
    in
    builtins.listToAttrs (
      map (p: {
        inherit (p) name;
        value = pkgs.callPackage (import (./. + "/${p.relPath}")) { };
      }) pkgList
    );

  overlay =
    final: _prev:
    let
      pkgList = findPackages ./.;
      flatAttrs = builtins.listToAttrs (
        map (p: {
          inherit (p) name;
          value = final.callPackage (import (./. + "/${p.relPath}")) { };
        }) pkgList
      );
      # 额外暴露分类集合：obsidianPlugins 与 zoteroPlugins
      obsidianPlugins = builtins.listToAttrs (
        map (p: {
          name = p.subName;
          value = flatAttrs.${p.name};
        }) (builtins.filter (p: p.category == "obsidian") pkgList)
      );
      zoteroPlugins = builtins.listToAttrs (
        map (p: {
          name = p.subName;
          value = flatAttrs.${p.name};
        }) (builtins.filter (p: p.category == "zotero") pkgList)
      );
    in
    flatAttrs
    // {
      inherit obsidianPlugins zoteroPlugins;
    };
}
