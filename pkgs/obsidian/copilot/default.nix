{
  callPackage,
  lib,
}:
let
  buildObsidianPlugin = callPackage ../build-obsidian-plugin.nix { };
in
buildObsidianPlugin {
  pname = "obsidian-copilot";
  version = "4.0.13";
  author = "logancyang";
  repo = "obsidian-copilot";
  hashJs = "sha256-38uJSfHbqBBsEIggEf9G7Yov8j0blRZLMrBounhhV+c=";
  hashManifest = "sha256-H1wrmzLQVYguUFQHwsv/m7RRrzfzBUuKAXcr2lyetMA=";
  hashCss = "sha256-RvLBkVjC/UX5o22OLItjcHYXAgWW0kB1a4uk2Asi+ck=";
  description = "A ChatGPT and LLM Copilot in Obsidian";
  homepage = "https://github.com/logancyang/obsidian-copilot";
  license = lib.licenses.mit;
}
