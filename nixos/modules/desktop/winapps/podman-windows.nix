{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.winapps;
  user = cfg.userName;
in
{
  config = lib.mkIf cfg.podman.enable {
    # 开启用户驻留，使容器服务随机器开机启动，而不是用户登录后才启动
    users.users.${user}.linger = true;

    # 确保存储目录和共享目录存在
    systemd.tmpfiles.rules = [
      "d ${cfg.podman.storagePath} 0755 ${user} users -"
      "d ${cfg.podman.sharedPath} 0755 ${user} users -"
    ];

    systemd.services.winapps-windows = {
      description = "WinApps Windows Subsystem Container (dockurr/windows)";
      after = [
        "network.target"
        "local-fs.target"
      ];
      wantedBy = lib.mkIf cfg.podman.autoStart [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=/run/user/${toString config.users.users.${user}.uid}"
        ];
        Restart = "always";
        RestartSec = "10s";
        TimeoutStopSec = "60s";
        ExecStartPre = [
          "-${pkgs.podman}/bin/podman rm -f WinApps"
        ];
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --name WinApps \
            --rm \
            --device=/dev/kvm \
            --cap-add=NET_ADMIN \
            -p 127.0.0.1:8006:8006 \
            -p 127.0.0.1:3389:3389/tcp \
            -p 127.0.0.1:3389:3389/udp \
            -e VERSION="${cfg.podman.version}" \
            -e LANGUAGE="${cfg.podman.language}" \
            -e RAM_SIZE="${cfg.podman.ramSize}" \
            -e CPU_CORES="${toString cfg.podman.cpuCores}" \
            -e TZ="${config.time.timeZone}" \
            -e ARGUMENTS="-device virtio-balloon-pci,id=balloon0,deflate-on-oom=on" \
            -v "${cfg.podman.storagePath}:/storage" \
            -v "/etc/winapps/oem:/oem:ro" \
            -v "${cfg.podman.sharedPath}:/shared" \
            docker.io/dockurr/windows:latest
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 30 WinApps";
      };
    };
  };
}
