{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.winapps;
  user = cfg.userName;
  userUid =
    if config.users.users ? ${user} && config.users.users.${user}.uid != null then
      toString config.users.users.${user}.uid
    else if config.ids.uids ? ${user} then
      toString config.ids.uids.${user}
    else
      "1000";
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
        "user-runtime-dir@${userUid}.service"
      ];
      wants = [
        "user-runtime-dir@${userUid}.service"
      ];
      wantedBy = lib.mkIf cfg.podman.autoStart [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=/run/user/${userUid}"
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
            --device=/dev/net/tun \
            --group-add keep-groups \
            --cap-add=NET_ADMIN \
            --cap-add=NET_RAW \
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
            docker.io/dockur/windows:latest
        '';
        ExecStop = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman unpause WinApps 2>/dev/null || true; ${pkgs.podman}/bin/podman stop -t 30 WinApps'";
      };
    };

    # 开机启动后自动休眠 (Suspend/Pause)，使 Windows 在开机完成启动后暂停以彻底释放 CPU (0% 占用)
    # 当用户后续点击 docx/xlsx 等文件时，WinApps 会以秒级速度直接 unpause 恢复运行
    systemd.services.winapps-boot-suspend = lib.mkIf (cfg.podman.autoStart && cfg.podman.autoSuspend) {
      description = "Suspend WinApps Windows container after boot to save CPU";
      after = [ "winapps-windows.service" ];
      wants = [ "winapps-windows.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=/run/user/${userUid}"
        ];
        TimeoutStartSec = "1200s";
        ExecStart = pkgs.writeShellScript "winapps-boot-suspend" ''
          set -euo pipefail
          echo "[winapps-boot-suspend] Waiting for WinApps container to start..."
          until [ "$(${pkgs.podman}/bin/podman inspect --format='{{.State.Status}}' WinApps 2>/dev/null || true)" = "running" ]; do
            sleep 3
          done

          echo "[winapps-boot-suspend] Waiting for Windows RDP service (port 3389) to be ready..."
          until ${pkgs.netcat}/bin/nc -z 127.0.0.1 3389 2>/dev/null; do
            STATUS=$(${pkgs.podman}/bin/podman inspect --format='{{.State.Status}}' WinApps 2>/dev/null || true)
            if [ "$STATUS" != "running" ]; then
              echo "[winapps-boot-suspend] Container is not running (status: $STATUS), aborting."
              exit 0
            fi
            sleep 5
          done

          echo "[winapps-boot-suspend] RDP is ready. Waiting ${toString cfg.podman.autoSuspendDelay}s for background initialization..."
          sleep ${toString cfg.podman.autoSuspendDelay}

          # Check if an active FreeRDP session is already running
          if ${pkgs.procps}/bin/pgrep -f "freerdp|wlfreerdp|xfreerdp" >/dev/null 2>&1; then
            echo "[winapps-boot-suspend] Active FreeRDP session detected. Skipping suspend."
            exit 0
          fi

          echo "[winapps-boot-suspend] Suspending WinApps container to save CPU..."
          ${pkgs.podman}/bin/podman pause WinApps
          echo "[winapps-boot-suspend] Successfully suspended WinApps container."
        '';
      };
    };
  };
}
