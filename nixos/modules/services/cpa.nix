{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.cpa;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.cpa = {
    enable = lib.mkEnableOption "CLIProxyAPI (CPA) - AI Account & CLI to API Proxy";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/eceasy/cli-proxy-api:latest";
      description = "Container image for CLIProxyAPI.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "cpa.${config.networking.domain}";
      description = "Public domain for CPA Management UI & API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.cpa;
      description = "Port for CPA service.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cpa";
      description = "State directory for CPA configuration and OAuth tokens.";
    };

    apiKeySecretKey = lib.mkOption {
      type = lib.types.str;
      default = "cpa/api_key";
      description = "SOPS secret path for CPA API key (OpenAI-compatible client key).";
    };
  };

  config = lib.mkIf cfg.enable {
    # 引用 SOPS 密钥：全局 password（管理密钥）与 CPA 专属 API Key
    sops.secrets = {
      "password" = { };
      ${cfg.apiKeySecretKey} = {
        restartUnits = [
          "cpa-init-config.service"
          "podman-cpa.service"
        ];
      };
    };

    # 确保配置目录与初始配置文件就绪，从 SOPS 读取管理密码与 API Key 生成 config.yaml
    systemd.services.cpa-init-config = {
      description = "Initialize CPA default configuration and unified credentials";
      wantedBy = [ "podman-cpa.service" ];
      before = [ "podman-cpa.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
                PASS="$(cat ${config.sops.secrets."password".path} | tr -d '\n\r')"

                install -d -m 0750 ${cfg.dataDir}
                install -d -m 0750 ${cfg.dataDir}/auth

                # CPA 管理密钥保存
                echo -n "$PASS" > ${cfg.dataDir}/management-key
                chmod 0600 ${cfg.dataDir}/management-key

                # 读取 SOPS 中的 CPA API Key（支持单行或多行多个 Key）
                API_KEYS=()
                if [ -f "${config.sops.secrets.${cfg.apiKeySecretKey}.path}" ]; then
                  while IFS= read -r line || [ -n "$line" ]; do
                    trimmed="$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                    if [ -n "$trimmed" ]; then
                      API_KEYS+=("$trimmed")
                    fi
                  done < "${config.sops.secrets.${cfg.apiKeySecretKey}.path}"
                fi

                # 如果未设置独立 API Key，兜底回退为全局 password
                if [ ''${#API_KEYS[@]} -eq 0 ]; then
                  API_KEYS=("$PASS")
                fi

                # 构建 YAML 数组列表，仅保留用户指定的 remote-management.secret-key 与 api-keys
                API_KEYS_YAML=""
                for k in "''${API_KEYS[@]}"; do
                  API_KEYS_YAML+="  - \"$k\""$'\n'
                done

                cat << EOF > ${cfg.dataDir}/config.yaml
        port: ${toString cfg.port}
        auth-dir: "/root/.cli-proxy-api"

        remote-management:
          secret-key: "$PASS"

        api-keys:
        $API_KEYS_YAML
        EOF
                chmod 0640 ${cfg.dataDir}/config.yaml
      '';
    };

    sops.templates."cpa-env" = {
      content = ''
        MANAGEMENT_PASSWORD=${config.sops.placeholder."password"}
      '';
    };

    virtualisation.oci-containers.containers.cpa = {
      inherit (cfg) image;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
      ];
      environmentFiles = [
        config.sops.templates."cpa-env".path
      ];
      volumes = [
        "${cfg.dataDir}/config.yaml:/CLIProxyAPI/config.yaml"
        "${cfg.dataDir}/auth:/root/.cli-proxy-api"
      ];
    };

    systemd.services.podman-cpa = {
      after = [ "cpa-init-config.service" ];
      requires = [ "cpa-init-config.service" ];
    };

    # Traefik 反向代理：统一通过 cpa.${domain} 访问 CPA 原生 WebUI 控制面板与 API
    services.traefik.proxies.cpa = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };

    # 状态持久化与快照备份
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/auth 0750 root root -"
    ];

    environment.global-persistence.directories = [
      cfg.dataDir
    ];

    services.restic.backups.borgbase.paths = [
      cfg.dataDir
    ];
  };
}
