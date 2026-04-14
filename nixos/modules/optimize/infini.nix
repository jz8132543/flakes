{
  lib,
  ...
}:
{
  imports = [ ./minimal.nix ];

  config = {
    services.traefik.enable = lib.mkForce false;
    services.tailscale.enable = lib.mkForce false;
    systemd.services.tailscale-setup.enable = lib.mkForce false;
    services.easytierMesh.enable = lib.mkForce false;
    services.nginx.enable = lib.mkForce false;
    # security.acme.certs = lib.mkForce { };
    security.acme.certs.main = lib.mkForce { };
    # security.acme.acceptTerms = lib.mkForce false;
  };
}
