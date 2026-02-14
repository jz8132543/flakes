{
  config,
  nixosModules,
  lib,
  ...
}:
{
  imports = [
    nixosModules.services.podman
  ];
  virtualisation.oci-containers.containers = {
    reader = {
      image = "hectorqin/reader";
      # entrypoint = null;
      # cmd = [
      #   "/bin/sh"
      #   "-c"
      #   # "/usr/bin/apt update && /usr/bin/apt-get install -y -q apt-utils dialog && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && /usr/bin/apt-get install -y -q faketime && /usr/bin/faketime -f '-3600d' /usr/bin/tini -- java -jar /app/bin/reader.jar"
      #   "sed -i 's/focal/jammy/g' /etc/apt/sources.list && /usr/bin/apt update && apt upgrade -y && /usr/bin/apt-get install -y -q apt-utils dialog && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && /usr/bin/apt-get install -y -q faketime && /usr/bin/faketime -f '-3600d' java -jar /app/bin/reader.jar"
      # ];
      # environment = {
      #   "READER_APP_CACHECHAPTERCONTENT" = "true";
      #   "READER_APP_SECURE" = "true";
      #   "READER_APP_SECUREKEY" = "gui159";
      #   "READER_APP_USERBOOKLIMIT" = "200";
      #   "READER_APP_USERLIMIT" = "5";
      #   "SPRING_PROFILES_ACTIVE" = "prod";
      # };
      environmentFiles = [ config.sops.templates."reader".path ];
      volumes = [
        # "/var/lib/reader/logs:/logs:rw"
        # "/var/lib/reader/storage:/storage:rw"
        "/var/lib/reader:/storage:rw"
      ];
      ports = [
        "${toString config.ports.reader}:8080/tcp"
      ];
      log-driver = "journald";
    };
  };
  sops.secrets = {
    "password" = { };
    "reader/password" = { };
  };
  sops.templates.reader = {
    content = ''
      READER_APP_CACHECHAPTERCONTENT=true
      READER_APP_SECURE=true
      READER_APP_SECUREKEY=${config.sops.placeholder."reader/password"}
      READER_APP_INVITECODE=${config.sops.placeholder."password"}
      READER_APP_DEFAULTUSERBOOKSOURCELIMIT=999999
      READER_APP_USERBOOKLIMIT=999999
      READER_APP_USERLIMIT=15
      SPRING_PROFILES_ACTIVE=prod
    '';
  };
  systemd.services."podman-reader" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "1000ms";
      RestartSteps = lib.mkOverride 90 9;
      StateDirectory = "reader";
      RuntimeDirectory = "reader";
      RuntimeDirectoryPreserve = "reader";
      WorkingDirectory = "/var/lib/reader";
      StateDirectoryMode = "0700";
      NoNewPrivileges = true;
    };
    after = [ "vaultwarden.service" ];
  };
  services.traefik.proxies.reader = {
    rule = "Host(`reader.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.reader}";
  };
}
