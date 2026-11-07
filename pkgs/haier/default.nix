{
  buildHomeAssistantComponent,
  sources,
  lib,
  ...
}:
buildHomeAssistantComponent {
  version = lib.removePrefix "v" sources.haier.version;
  inherit (sources.haier) src;
  owner = "banto6";
  domain = "haier";
  meta = {
    description = "Haier Home Assistant integration";
    homepage = "https://github.com/banto6/haier";
    license = lib.licenses.asl20;
  };
}
