{
  buildHomeAssistantComponent,
  fetchFromGitHub,
  lib,
  ...
}:
let
  version = "b5cd1f03c6f99e0f1824a5600456e5c53b57ed4e";
  src = fetchFromGitHub {
    owner = "banto6";
    repo = "haier";
    rev = version;
    fetchSubmodules = false;
    sha256 = "sha256-9eRSEL1pVbC4mquL0D4lwFvmethMidK1S+W+e3rI5s8=";
  };
in
buildHomeAssistantComponent {
  inherit version src;
  owner = "banto6";
  domain = "haier";
  meta = {
    description = "Haier Home Assistant integration";
    homepage = "https://github.com/banto6/haier";
    license = lib.licenses.asl20;
  };
}
