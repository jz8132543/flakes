{
  callPackage,
  lib,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-zotero-desktop-connector";
  version = "3.2.1";
  author = "community-archive";
  repo = "obsidian-zotero-integration";
  hashJs = "sha256-QVgkSNeQ17mkaRwA/0bdoJsPO76gLInQk8xAGN/BQDI=";
  hashManifest = "sha256-wY8lKh+SEIVGe6gj19Jyo2nmXj8wAR9vlViuQgGROVw=";
  hashCss = "sha256-PqaYiqtsRRg9xpyF1Yc3h9y70NdiZPIRwHuEAPnbwGo=";
  description = "Insert and link citations and bibliographies from Zotero";
  homepage = "https://github.com/mgmeyers/obsidian-zotero-desktop-connector";
  license = lib.licenses.mit;
}
