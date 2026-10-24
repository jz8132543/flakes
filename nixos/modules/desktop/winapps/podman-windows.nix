{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.winapps;
  user = cfg.userName;
  userUid =
    if config.users.users ? ${user} && config.users.users.${user}.uid != null then
      toString config.users.users.${user}.uid
    else if config.ids.uids ? ${user} then
      toString config.ids.uids.${user}
    else
      "1000";

  # The upstream client and NixOS service must control the same Compose project.
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
    # Based on upstream WinApps compose.yaml; adapted for rootless Podman,
    # persistent host paths and the local xrdp port conflict.
    name: "winapps"

    services:
      windows:
        image: ${cfg.podman.image}
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
          - ${cfg.podman.sharedPath}:/shared
    ${lib.optionalString (
      cfg.activation.windowsProductKeyFile != null
    ) "      - ${cfg.activation.windowsProductKeyFile}:/oem/windows-product-key:ro"}
    ${lib.optionalString (
      cfg.activation.officeProductKeyFile != null
    ) "      - ${cfg.activation.officeProductKeyFile}:/oem/office-product-key:ro"}
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
          ExecStart = "${compose} up -d";
          ExecStop = "${compose} stop";
        };
      };

      # Optional one-time boot pause. Runs once after boot, waits for the configured
      # delay, and pauses the container if guest provisioning is complete and no
      # FreeRDP session is active. Normal idle pause/resume is handled upstream.
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
          TimeoutStartSec = "${toString (cfg.podman.autoSuspendDelay + 60)}s";
          ExecStart = pkgs.writeShellScript "winapps-boot-suspend" ''
            set -eu
            sleep ${toString cfg.podman.autoSuspendDelay}

            if [ ! -e ${lib.escapeShellArg "${cfg.podman.sharedPath}/.winapps-provisioned"} ]; then
              echo "[winapps-boot-suspend] Provisioning not yet complete, skipping boot pause."
              exit 0
            fi

            if ${pkgs.procps}/bin/pgrep -f "freerdp|wlfreerdp|xfreerdp" >/dev/null 2>&1; then
              echo "[winapps-boot-suspend] Active FreeRDP session detected, skipping boot pause."
              exit 0
            fi

            state="$(${pkgs.podman}/bin/podman inspect --format='{{.State.Status}}' WinApps 2>/dev/null || true)"
            case "$state" in
              running)
                echo "[winapps-boot-suspend] Pausing WinApps container after boot..."
                ${compose} pause
                ;;
              *)
                echo "[winapps-boot-suspend] Container in state '$state', skipping pause."
                ;;
            esac
          '';
        };
      };
    };
  };
}
