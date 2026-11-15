{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.workbuddy2api-hub;
  unit = "podman-workbuddy2api-hub.service";
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.workbuddy2api-hub = {
    enable = lib.mkEnableOption "WorkBuddy2API-Hub multi-account API gateway";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/ardeyouxipianyi/workbuddy2api-hub:latest";
      description = "Container image for WorkBuddy2API-Hub.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "workbuddy.${config.networking.domain}";
      description = "Public domain for the WorkBuddy dashboard and API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.workbuddy2api-hub;
      description = "Loopback port exposed to Traefik.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/workbuddy2api-hub";
      description = "Persistent account credentials, settings and usage data.";
    };

    apiKeySecretKey = lib.mkOption {
      type = lib.types.str;
      default = "openai_api_key";
      description = "SOPS secret for the OpenAI-compatible client API key, shared with CPA.";
    };

    panelPasswordSecretKey = lib.mkOption {
      type = lib.types.str;
      default = "password";
      description = "SOPS secret for the dashboard password.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      ${cfg.apiKeySecretKey}.restartUnits = [ unit ];
      ${cfg.panelPasswordSecretKey}.restartUnits = [ unit ];
    };

    sops.templates."workbuddy2api-hub-env" = {
      mode = "0600";
      restartUnits = [ unit ];
      content = ''
        API_KEY=${config.sops.placeholder.${cfg.apiKeySecretKey}}
      '';
    };

    virtualisation.oci-containers.containers.workbuddy2api-hub = {
      inherit (cfg) image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:8788" ];
      extraOptions = [ "--pull=missing" ];
      # Upstream prints the API key on stdout at every start. Keep stderr logs.
      cmd = [
        "sh"
        "-c"
        "exec python -m wb_proxy --host 0.0.0.0 --lan >/dev/null"
      ];
      environment = {
        HOST = "0.0.0.0";
        PORT = "8788";
        TZ = config.time.timeZone;
        WB_MEDIA_DIR = "/app/usage/media";
        WB_PROXY_CATALOG_DIR = "/app/usage/catalog";
      };
      environmentFiles = [ config.sops.templates."workbuddy2api-hub-env".path ];
      volumes = [
        "${cfg.dataDir}/accounts:/app/accounts"
        "${cfg.dataDir}/usage:/app/usage"
        "${cfg.dataDir}/subbridge-data:/app/subbridge-data"
      ];
    };

    systemd.services.podman-workbuddy2api-hub = {
      after = [
        "systemd-tmpfiles-setup.service"
        "sops-install-secrets.service"
      ];
      requires = [ "sops-install-secrets.service" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      serviceConfig.UMask = "0077";
      preStart = ''
        ${pkgs.python3}/bin/python3 ${./workbuddy2api-hub-init.py} \
          ${lib.escapeShellArg "${cfg.dataDir}/accounts"} \
          ${lib.escapeShellArg config.sops.secrets.${cfg.apiKeySecretKey}.path} \
          ${lib.escapeShellArg config.sops.secrets.${cfg.panelPasswordSecretKey}.path}
      '';
    };

    services.traefik.proxies.workbuddy2api-hub = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
      "d ${cfg.dataDir}/accounts 0700 root root -"
      "d ${cfg.dataDir}/usage 0700 root root -"
      "d ${cfg.dataDir}/subbridge-data 0700 root root -"
    ];
    environment.global-persistence.directories = [ cfg.dataDir ];
    services.restic.backups.borgbase.paths = [ cfg.dataDir ];
  };
}
