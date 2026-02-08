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
        "electron-27.3.11"
        "nix-2.24.5"
      ];
      allowUnfreePackages = [
        "terraform"
        "vscode"
      ];
    };
    overlays = packages ++ [ lateFixes ] ++ lastePackages;
  };
}
