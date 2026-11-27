{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.openhands;
  appPort = config.ports.openhands;
  builtinSkills = pkgs.runCommand "openhands-builtin-skills" { } ''
    mkdir -p "$out/deep-research" "$out/workspace-management"
    cp ${./skills/deep-research/SKILL.md} "$out/deep-research/SKILL.md"
    cp ${./skills/workspace-management/SKILL.md} "$out/workspace-management/SKILL.md"
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.skillsDir}/nixos-builtin 0755 root root - -" ];

    virtualisation.oci-containers.containers.openhands = {
      inherit (cfg) image;
      ports = [ "127.0.0.1:${toString appPort}:8000" ];
      environmentFiles = [ config.sops.templates."openhands-gateway.env".path ];
      environment = {
        AGENT_CANVAS_ALLOW_LAN_SESSION_KEY = "true";
        AUTOMATION_BASE_URL = "https://${cfg.domain}";
        OPENAI_API_BASE = cfg.gatewayBaseUrl;
        OH_ENABLE_VSCODE = "false";
        UV_CACHE_DIR = "/home/openhands/.openhands/cache/uv";
        NPM_CONFIG_CACHE = "/home/openhands/.openhands/cache/npm";
      };
      volumes = [
        "${cfg.dataDir}/state:/home/openhands/.openhands"
        "${cfg.dataDir}/knowledge:/knowledge:rw"
        "${cfg.dataDir}/workspace:/workspace:rw"
        "${cfg.skillsDir}:/home/openhands/.openhands/microagents:ro"
        "${builtinSkills}:/home/openhands/.openhands/microagents/nixos-builtin:ro"
        "${cfg.dataDir}/outputs:/outputs:rw"
      ];
      extraOptions = [
        "--security-opt=no-new-privileges"
        "--cap-drop=ALL"
        "--pids-limit=${toString cfg.container.pidsLimit}"
        "--memory=${cfg.container.memoryMax}"
        "--cpus=${cfg.container.cpus}"
      ]
      ++ lib.optional (!cfg.network.enable) "--add-host=${config.services.new-api.domain}:host-gateway";
      labels."io.containers.autoupdate" = "disabled";
      log-driver = "journald";
    };
    systemd.services.podman-openhands = {
      after = [
        "sops-install-secrets.service"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [
        "sops-install-secrets.service"
        "systemd-tmpfiles-setup.service"
      ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        "/var/lib/containers"
      ];
      serviceConfig = {
        MemoryMax = cfg.container.memoryMax;
        CPUQuota = cfg.container.cpuQuota;
        TasksMax = cfg.container.pidsLimit;
      };
    };

  };
}
