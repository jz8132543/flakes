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

  # WinApps 客户端 (~/.config/winapps/compose.yaml) 与本服务共用同一个 compose 文件，
  # 使 AUTOPAUSE 的 pause/unpause 与系统级开机启动操作完全一致的容器。
  composeFile = "/etc/winapps/compose.yaml";

  # nixpkgs 的 podman-compose 未将 podman 打入 PATH，而 systemd 服务环境极简，
  # 这里包一层 wrapper 保证 podman/slirp4netns/newuidmap(/run/wrappers/bin) 可达。
  podmanCompose = pkgs.writeShellScriptBin "podman-compose-winapps" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.podman
        pkgs.slirp4netns
      ]
    }:/run/wrappers/bin:$PATH"
    exec ${pkgs.podman-compose}/bin/podman-compose "$@"
  '';
  compose = "${podmanCompose}/bin/podman-compose-winapps --file ${composeFile}";

  # 参照 WinApps 官方 compose.yaml 生成，供 podman-compose 管理容器生命周期
  # 注意：必须指定 network_mode: "slirp4netns"。
  # 原因：宿主机启用了 DN42 等复杂网络，路由表条目超 8000+ 条；
  # Podman 默认的 pasta 网络后端在复制宿主机路由表时会因 Netlink 缓冲区溢出 (Argument list too long) 导致容器启动崩溃 (exit 125)。
  # slirp4netns 采用独立用户态协议栈，完全不受宿主机路由膨胀影响。
  composeYaml = ''
    # WinApps compose configuration (NixOS managed)
    # Consumed by both the winapps client (AUTOPAUSE) and the winapps-windows service.
    name: "winapps"

    services:
      windows:
        image: docker.io/dockurr/windows:latest
        container_name: WinApps
        network_mode: "slirp4netns"
        environment:
          VERSION: "${cfg.podman.version}"
          LANGUAGE: "${cfg.podman.language}"
          RAM_SIZE: "${cfg.podman.ramSize}"
          CPU_CORES: "${toString cfg.podman.cpuCores}"
          DISK_SIZE: "${cfg.podman.diskSize}"
          USERNAME: "${cfg.podman.username}"
          PASSWORD: "${cfg.podman.password}"
          TZ: "${config.time.timeZone}"
          BALLOONING: "${if cfg.podman.ballooning then "Y" else "N"}"
        devices:
          - /dev/kvm
          - /dev/net/tun
        cap_add:
          - NET_ADMIN
          - NET_RAW
        group_add:
          - keep-groups
        ports:
          - "127.0.0.1:8006:8006"
          - "127.0.0.1:${toString cfg.podman.port}:3389/tcp"
          - "127.0.0.1:${toString cfg.podman.port}:3389/udp"
        volumes:
          - ${cfg.podman.storagePath}:/storage
          - /etc/static/winapps/oem:/oem:ro
          - /nix/store:/nix/store:ro
          - ${cfg.podman.sharedPath}:/shared
        restart: on-failure
        stop_grace_period: 120s
  '';
in
{
  config = lib.mkIf cfg.podman.enable {
    # 开启用户驻留，使容器服务随机器开机启动，而不是用户登录后才启动
    users.users.${user}.linger = true;

    environment.etc."winapps/compose.yaml".text = composeYaml;

    systemd = {
      # 确保存储目录和共享目录存在
      tmpfiles.rules = [
        "d ${cfg.podman.storagePath} 0755 ${user} users -"
        "d ${cfg.podman.sharedPath} 0755 ${user} users -"
      ];

      # 开机自动启动 Windows 容器（由 podman-compose 按官方 compose.yaml 管理）
      services.winapps-windows = {
        description = "WinApps Windows Subsystem Container (dockur/windows)";
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
          Type = "oneshot";
          RemainAfterExit = true;
          User = user;
          Group = "users";
          Environment = [
            "XDG_RUNTIME_DIR=/run/user/${userUid}"
          ];
          Restart = "on-failure";
          RestartSec = "15s";
          # 首次运行需要拉取镜像并安装 Windows，预留充足时间
          TimeoutStartSec = "1800s";
          TimeoutStopSec = "180s";
          ExecStartPre = [
            # 清理历史遗留的裸 podman run 容器，统一交由 compose 管理（磁盘数据保留在绑定挂载中）
            "-${podmanCompose}/bin/podman-compose-winapps --file ${composeFile} down"
            "-${pkgs.podman}/bin/podman rm -f WinApps"
          ];
          ExecStart = "${compose} up -d";
          ExecStop = "${compose} down";
        };
      };

      # 开机启动后自动休眠 (Suspend/Pause)，使 Windows 完成启动后立即暂停以彻底释放 CPU (0% 占用)
      # 说明：日常使用中的“闲置自动挂起”由 WinApps 官方 AUTOPAUSE 配置负责（见 winapps.conf），
      # 此处仅覆盖“开机后、用户尚未打开任何文件”的时间窗口。
      # 当用户后续点击 docx/xlsx 等文件时，WinApps 会检测到 paused 状态并自动 unpause 恢复运行。
      services.winapps-boot-suspend = lib.mkIf (cfg.podman.autoStart && cfg.podman.autoSuspend) {
        description = "Suspend WinApps Windows container after boot to save CPU";
        after = [ "winapps-windows.service" ];
        wants = [ "winapps-windows.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = user;
          Group = "users";
          Environment = [
            "XDG_RUNTIME_DIR=/run/user/${userUid}"
          ];
          TimeoutStartSec = "1800s";
          ExecStart = pkgs.writeShellScript "winapps-boot-suspend" ''
            set -eu

            echo "[winapps-boot-suspend] Waiting for the WinApps container to start..."
            until [ "$(${pkgs.podman}/bin/podman inspect --format='{{.State.Status}}' WinApps 2>/dev/null || true)" = "running" ]; do
              sleep 5
            done

            echo "[winapps-boot-suspend] Waiting for Windows RDP service (port ${toString cfg.podman.port}) to truly respond..."
            # 注意：不能使用简单的 nc -z，因为宿主机 rootlessport 会在容器刚起时就立即接受握手（哪怕虚拟机内 Windows 还没就绪）。
            # 这里发送真实 RDP X.224 连接握手包，只有内部 Windows RDP 真正应答时才判定就绪。
            until timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${toString cfg.podman.port} && echo -ne "\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00" >&3 && head -c 1 <&3' >/dev/null 2>&1; do
              if [ "$(${pkgs.podman}/bin/podman inspect --format='{{.State.Status}}' WinApps 2>/dev/null || true)" != "running" ]; then
                echo "[winapps-boot-suspend] Container is no longer running. Aborting."
                exit 0
              fi
              sleep 5
            done

            echo "[winapps-boot-suspend] RDP is ready. Waiting ${toString cfg.podman.autoSuspendDelay}s for background initialization..."
            sleep ${toString cfg.podman.autoSuspendDelay}

            # 若用户已经在使用 Windows（存在 FreeRDP 会话），则跳过挂起
            if ${pkgs.procps}/bin/pgrep -f "freerdp|wlfreerdp|xfreerdp" >/dev/null 2>&1; then
              echo "[winapps-boot-suspend] Active FreeRDP session detected. Skipping suspend."
              exit 0
            fi

            echo "[winapps-boot-suspend] Pausing the WinApps container (CPU usage drops to 0%)..."
            ${compose} pause
            echo "[winapps-boot-suspend] Done."
          '';
        };
      };
    };
  };
}
