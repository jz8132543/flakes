{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.metapi;
  secretsDir = "${cfg.dataDir}-secrets";
  credentialsFile = "/run/metapi/environment";
  credentialsSetup = pkgs.writeShellScript "metapi-credentials-setup" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg cfg.dataDir}
    ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg secretsDir}
    ${pkgs.coreutils}/bin/install -d -m 0700 /run/metapi
    auth_token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < ${
      lib.escapeShellArg config.sops.secrets."password".path
    })"
    if [ -z "$auth_token" ]; then
      echo "Metapi AUTH_TOKEN secret is empty" >&2
      exit 1
    fi

    for name in PROXY_TOKEN ACCOUNT_CREDENTIAL_SECRET; do
      file=${lib.escapeShellArg secretsDir}/"$name"
      if [ ! -s "$file" ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > "$file"
        ${pkgs.coreutils}/bin/chmod 0600 "$file"
      fi
    done

    tmp=${lib.escapeShellArg credentialsFile}.tmp
    {
      printf 'AUTH_TOKEN=%s\n' "$auth_token"
      printf 'PROXY_TOKEN=%s\n' "$(< ${lib.escapeShellArg secretsDir}/PROXY_TOKEN)"
      printf 'ACCOUNT_CREDENTIAL_SECRET=%s\n' "$(< ${lib.escapeShellArg secretsDir}/ACCOUNT_CREDENTIAL_SECRET)"
      printf 'PORT=4000\nDATA_DIR=/app/data\nTZ=%s\nTRUSTED_PROXIES=127.0.0.1\n' ${lib.escapeShellArg config.time.timeZone}
    } > "$tmp"
    ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" ${lib.escapeShellArg credentialsFile}
  '';
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.metapi = {
    enable = lib.mkEnableOption "Metapi unified AI gateway";

    image = lib.mkOption {
      type = lib.types.str;
      default = "1467078763/metapi:latest";
      description = "Metapi container image.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "metapi.${config.networking.domain}";
      description = "Public hostname for Metapi.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.metapi;
      description = "Loopback port exposed to Traefik.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/metapi";
      description = "Persistent Metapi database and generated credentials.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."password" = {
      restartUnits = [ "podman-metapi.service" ];
    };

    virtualisation.oci-containers.containers.metapi = {
      inherit (cfg) image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:4000" ];
      environmentFiles = [ credentialsFile ];
      volumes = [ "${cfg.dataDir}:/app/data" ];
      labels."io.containers.autoupdate" = "";
      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--umask=0077"
      ];
    };

    systemd.services.podman-metapi = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        secretsDir
      ];
      serviceConfig.UMask = "0077";
      preStart = "${credentialsSetup}";
    };

    services.traefik.proxies.metapi = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
      "d ${secretsDir} 0700 root root -"
    ];
    environment.global-persistence.directories = [
      cfg.dataDir
      secretsDir
    ];
    services.restic.backups.borgbase.paths = [
      cfg.dataDir
      secretsDir
    ];
  };
}
