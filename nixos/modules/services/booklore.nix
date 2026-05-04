{
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  domain = "booklore.${config.networking.domain}";
  port = config.ports.booklore or 6060;
  dataDir = "/var/lib/booklore";
  dbPort = 5432;
  dbName = "booklore";
  dbUser = "booklore";
  adminUsername = "i";
  adminName = "BookLore Admin";
  adminEmail = "i@${config.networking.domain}";
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
  ];

  sops.secrets = {
    "password" = { };
  };

  sops.templates."booklore-env".content = ''
    USER_ID=1000
    GROUP_ID=1000
    TZ=${config.time.timeZone}
    SERVER_PORT=${toString port}
    SERVER_ADDRESS=127.0.0.1
    DATABASE_URL=jdbc:postgresql://127.0.0.1:${toString dbPort}/${dbName}
    DATABASE_USERNAME=${dbUser}
    DATABASE_PASSWORD=""
    DISK_TYPE=LOCAL
    APP_PATH_CONFIG=${dataDir}/config
    APP_BOOKDROP_FOLDER=${dataDir}/bookdrop
  '';

  virtualisation.oci-containers.containers.booklore = {
    image = "ghcr.io/booklore-app/booklore:latest";
    extraOptions = [ "--network=host" ];
    environmentFiles = [ config.sops.templates."booklore-env".path ];
    volumes = [
      "${dataDir}/data:/app/data"
      "${dataDir}/books:/books"
      "${dataDir}/bookdrop:/bookdrop"
    ];
    log-driver = "journald";
  };

  services.traefik.proxies.booklore = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:${toString port}";
  };

  environment.global-persistence.directories = [
    dataDir
  ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${dataDir}/config 0755 root root -"
    "d ${dataDir}/data 0755 root root -"
    "d ${dataDir}/books 0755 root root -"
    "d ${dataDir}/bookdrop 0755 root root -"
    "d ${dataDir}/postgres 0755 root root -"
  ];

  systemd.services.booklore-bootstrap = {
    description = "Provision the initial BookLore admin user";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "podman-booklore.service"
      "podman-booklore-db.service"
    ];
    after = [
      "network-online.target"
      "podman-booklore-db.service"
      "podman-booklore.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      base_url="http://127.0.0.1:${toString port}"
      status="$(${pkgs.curl}/bin/curl --fail --silent --show-error --retry 60 --retry-delay 2 --retry-all-errors --retry-connrefused "''${base_url}/api/v1/setup/status")"

      if printf '%s' "$status" | ${pkgs.jq}/bin/jq -e '.data == true' >/dev/null; then
        exit 0
      fi

      password="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."password".path})"
      payload="$(${pkgs.jq}/bin/jq -nc \
        --arg username '${adminUsername}' \
        --arg email '${adminEmail}' \
        --arg name '${adminName}' \
        --arg password "$password" \
        '{username:$username,email:$email,name:$name,password:$password}')"

      ${pkgs.curl}/bin/curl --fail --silent --show-error \
        --request POST \
        --header 'Content-Type: application/json' \
        --data "$payload" \
        "''${base_url}/api/v1/setup"
    '';
  };
}
