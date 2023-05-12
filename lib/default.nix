{ inputs
, lib
,
}:
lib.makeExtensible (self: {
  data = lib.importJSON ./data/data.json;
  flakeStateVersion = lib.importJSON ./state-version.json;
  buildModuleList = import ./build-module-list.nix { inherit self lib; };
  flattenTree = import ./flatten-tree.nix { inherit lib; };
  rakeLeaves = import ./rake-leaves.nix { inherit inputs lib; };
  rake = import ./rake.nix { inherit inputs lib; };
})
