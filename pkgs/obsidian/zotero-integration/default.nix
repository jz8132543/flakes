{
  callPackage,
  lib,
  sources,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-zotero-desktop-connector";
  main = sources.obsidian-zotero-integration-js;
  manifest = sources.obsidian-zotero-integration-manifest;
  css = sources.obsidian-zotero-integration-css or null;
  description = "Insert and link citations and bibliographies from Zotero";
  homepage = "https://github.com/mgmeyers/obsidian-zotero-desktop-connector";
  license = lib.licenses.mit;
}
