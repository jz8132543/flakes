{
  callPackage,
  lib,
  sources,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-livesync";
  main = sources.obsidian-livesync-js;
  manifest = sources.obsidian-livesync-manifest;
  css = sources.obsidian-livesync-css or null;
  description = "Self-hosted live synchronization plugin for Obsidian using CouchDB";
  homepage = "https://github.com/vrtmrz/obsidian-livesync";
  license = lib.licenses.mit;
}
