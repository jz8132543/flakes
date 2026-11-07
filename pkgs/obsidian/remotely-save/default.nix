{
  callPackage,
  lib,
  sources,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "remotely-save";
  main = sources.obsidian-remotely-save-js;
  manifest = sources.obsidian-remotely-save-manifest;
  css = sources.obsidian-remotely-save-css or null;
  description = "Sync Obsidian vault with WebDAV/S3/OneDrive/Dropbox";
  homepage = "https://github.com/remotely-save/remotely-save";
  license = lib.licenses.mit;
}
