{
  pkgs,
  lib,
  ...
}:
lib.mkMerge [
  {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings = {
        network_interface = "podman0";
        dns_enabled = true;
      };
    };
    virtualisation.oci-containers.backend = "podman";
  }
  {
    environment.systemPackages = with pkgs; [
      podman-compose
      distrobox
    ];
    environment.global-persistence.user = {
      directories = [
        ".local/share/containers"
      ];
    };
  }
]
