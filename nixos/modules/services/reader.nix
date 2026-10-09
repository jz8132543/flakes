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
      image = "docker.cnb.cool/hectorqin/reader:main";
      environmentFiles = [ config.sops.templates."reader".path ];
      volumes = [
        "/var/lib/reader:/data:rw"
        "/var/lib/reader:/storage:rw"
      ];
      ports = [
        "${toString config.ports.reader}:5888/tcp"
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
      RuntimeDirectory = "reader";
      RuntimeDirectoryPreserve = "reader";
      NoNewPrivileges = true;
    };
    after = [ "vaultwarden.service" ];
  };
  services.traefik.proxies.reader = {
    rule = "Host(`reader.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.reader}";
  };
}
