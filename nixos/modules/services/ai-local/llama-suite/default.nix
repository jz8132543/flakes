{ nixosModules, ... }:
{
  nix.settings = {
    extra-substituters = [ "https://cache.lantian.pub/lantian" ];
    extra-trusted-public-keys = [
      "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ="
    ];
  };

  imports = [
    nixosModules.services.ai-local.settings
    nixosModules.services.ai-local."llama-suite".llama-cpp
    nixosModules.services.ai-local."llama-suite".llama-swap
  ];
}
