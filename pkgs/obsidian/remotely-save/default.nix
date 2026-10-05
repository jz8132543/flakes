{
  callPackage,
  lib,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "remotely-save";
  version = "0.5.25";
  author = "remotely-save";
  repo = "remotely-save";
  hashJs = "sha256-s6+9J/FRiLl4RhjJWGB4abqkNNwKvPByd0+ZNiwR+gQ=";
  hashManifest = "sha256-cdnAthYAPzppaIDnqogpblsxVVdX6TOhLSkAuWxMqpA=";
  hashCss = "sha256-h1hOfVOMpYxSevuyYlsJ6igryue/eEt8zjPKkung37M=";
  description = "Sync Obsidian vault with WebDAV/S3/OneDrive/Dropbox";
  homepage = "https://github.com/remotely-save/remotely-save";
  license = lib.licenses.mit;
}
