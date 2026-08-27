{ config, lib, ... }:

let
  cfg = config.desktop.winapps;
in
{
  config = lib.mkIf cfg.docker.enable {
    # Ensure podman/docker backend is available. Using podman by default in NixOS for containers is common.
    virtualisation.oci-containers = {
      backend = "podman";
      containers.winapps-windows = {
        image = "docker.io/dockurr/windows";
        environment = {
          VERSION = "tiny10";
          RAM_SIZE = "4G";
          CPU_CORES = "4";
          TZ = config.time.timeZone;
          ARGUMENTS = "-rtc base=localtime,clock=host,driftfix=slew";
        };
        ports = [
          "8006:8006"
          "13389:3389/tcp"
          "13389:3389/udp"
        ];
        volumes = [
          "/var/lib/winapps-docker:/storage"
        ];
        extraOptions = [
          "--device=/dev/kvm"
          "--cap-add=NET_ADMIN"
        ]
        ++ lib.optional cfg.enableCdrom "--device=/dev/cdrom";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/winapps-docker 0755 root root -"
    ];
  };
}
