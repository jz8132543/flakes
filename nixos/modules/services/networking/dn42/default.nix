{
  lib,
  ...
}:
{
  imports = [
    ./base.nix
    ./mesh.nix
    ./edge.nix
  ];

  services.dn42.role = lib.mkDefault "border";
}
