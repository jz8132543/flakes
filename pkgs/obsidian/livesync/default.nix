{
  callPackage,
  lib,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-livesync";
  version = "1.0.34";
  author = "vrtmrz";
  repo = "obsidian-livesync";
  hashJs = "sha256-RdZWf3rE44NuklGdtFT0Fb618cKqGMTEaVG+cRPXf18=";
  hashManifest = "sha256-fAKyVtlYHaLw7axku6gQRlKBS0/N6BapyRpfTigWgns=";
  hashCss = "sha256-S6AL70F+6Y2aYt2f67eS3GVVlJz8no4GlFCtaZqyufA=";
  description = "Self-hosted live synchronization plugin for Obsidian using CouchDB";
  homepage = "https://github.com/vrtmrz/obsidian-livesync";
  license = lib.licenses.mit;
}
