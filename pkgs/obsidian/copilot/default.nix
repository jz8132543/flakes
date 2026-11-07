{
  callPackage,
  lib,
  sources,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-copilot";
  main = sources.obsidian-copilot-js;
  manifest = sources.obsidian-copilot-manifest;
  css = sources.obsidian-copilot-css or null;
  description = "A ChatGPT and LLM Copilot in Obsidian";
  homepage = "https://github.com/logancyang/obsidian-copilot";
  license = lib.licenses.mit;
}
