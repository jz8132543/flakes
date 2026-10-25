{
  inputs,
  lib,
  self,
  ...
}:
let
  packages = import ../../../lib/overlays.nix { inherit inputs lib self; };
in
{
  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = true;
      nvidia.acceptLicense = true;
      binary-caches-parallel-connections = 16;
      permittedInsecurePackages = [
        "openssl-1.1.1w"
        "nix-2.24.5"
        "olm-3.2.16"
        "minio-client-2025-08-13T08-35-41Z"
        "electron-39.8.10"
      ];
      allowUnfreePackages = [
        "terraform"
        "vscode"
      ];
    };
    overlays = packages;
  };
}
