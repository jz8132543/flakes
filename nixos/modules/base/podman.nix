{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkMerge
[
  lib.mkIf
  config.virtualisation.docker.enabled
  {
    systemd = {
      timers.docker-prune = {
        wantedBy = ["timers.target"];
        partOf = ["docker-prune.service"];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };
      services.docker-prune = {
        serviceConfig.Type = "oneshot";
        script = ''
          ${pkgs.docker}/bin/docker system prune --all --force
        '';
        requires = ["docker.service"];
      };
    };
  }
  lib.mkIf
  config.virtualisation.podman.enabled
  {
    systemd.user = {
      services = {
        "podman-prune" = {
          description = "Cleanup podman images";
          requires = ["podman.socket"];
          after = ["podman.socket"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.podman} image prune --all --external --force";
          };
        };
      };
      timers."podman-prune" = {
        partOf = ["podman-prune.service"];
        timerConfig = {
          OnCalendar = "weekly";
          RandomizedDelaySec = "900";
          Persistent = "true";
        };
      };
    };
  }
]
