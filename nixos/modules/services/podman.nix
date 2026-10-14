{
  pkgs,
  config,
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
        options = {
          mtu = "1500";
        };
      };
    };
    virtualisation.containers.registries.settings = {
      unqualified-search-registries = [ "docker.io" ];
      # 使用镜像加速来避免 Docker Hub 速率限制
      docker.io = {
        mirrors = [
          "docker.m.daocloud.io"
          "dockerproxy.com"
        ];
      };
    };
    virtualisation.oci-containers.backend = "podman";
  }
  {
    # 1. 声明 secret
    sops.secrets."docker_hub_auth" = { };

    # 2. 渲染配置文件
    sops.templates."docker_auth.json" = {
      content = ''
        {
          "auths": {
            "https://index.docker.io/v1/": {
              "auth": "${config.sops.placeholder.docker_hub_auth}"
            },
            "docker.io": {
              "auth": "${config.sops.placeholder.docker_hub_auth}"
            }
          }
        }
      '';
      owner = "root";
      group = "root";
      # 注意权限：
      # 如果只给 root 和 oci-containers(默认也是root) 用，写 0600 即可。
      # 如果你想让普通用户(如 tippy)在终端直接用 podman pull 也能享受加速，写 0644。
      mode = "0644";
    };

    # ------------------------------------------------------------------
    # 3. 针对 oci-containers / Podman 后台服务的全局注入 (最核心)
    # 将环境变量注入到 systemd 的全局环境中。
    # 这样一来，NixOS 自动生成的所有 podman-*.service，
    # 以及 podman-auto-update.service (用于镜像自动更新)，都会默认带上这个凭证！
    # ------------------------------------------------------------------
    systemd.globalEnvironment = {
      REGISTRY_AUTH_FILE = config.sops.templates."docker_auth.json".path;
    };

    # 4. 针对普通终端交互 (如你手动敲 podman pull)
    environment.variables = {
      REGISTRY_AUTH_FILE = config.sops.templates."docker_auth.json".path;
    };

    # 5. 针对原生 Docker Daemon 引擎 (如果你启用了 virtualisation.docker)
    # Docker Daemon 作为系统级服务运行，默认会自动读取 /root/.docker/config.json
    systemd.tmpfiles.rules = [
      "d /root/.docker 0700 root root -"
      "L+ /root/.docker/config.json - - - - ${config.sops.templates."docker_auth.json".path}"
    ];
  }
  {
    networking.firewall = {
      # 信任 Podman 的虛擬網卡介面
      trustedInterfaces = [ "podman0" ];

      # 如果你使用的是 Rootless 模式，或者自定義了 Podman 網絡，
      # 建議直接放行 Podman 的常用網段（例如 10.88.0.0/16 或 10.89.0.0/16）：
      # extraCommands = ''
      #   iptables -A INPUT -s 10.88.0.0/13 -j ACCEPT
      # '';
    };
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
